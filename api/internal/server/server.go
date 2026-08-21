// Package server builds the HTTP server and top-level route table.
package server

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/hibiken/asynq"

	"github.com/anhad/api/internal/auth"
	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/japa"
	"github.com/anhad/api/internal/moderation"
	"github.com/anhad/api/internal/reels"
	"github.com/anhad/api/internal/social"
	"github.com/anhad/api/internal/store"
)

// New assembles the HTTP route table and the moderation-pipeline worker
// that runs alongside it. They're returned separately (not one bundled
// type) because main.go starts and stops each with http.Server/asynq.Server's
// own existing methods rather than a new abstraction wrapping both.
//
// Returns an error rather than panicking so main.go can fail startup the
// same way store.Connect already does — local video storage needs to
// create a directory on disk (internal/reels.NewLocalVideoStorage), and
// the moderation pipeline needs a reachable whisper-cli binary
// (internal/moderation.BuildPipeline) — both worth failing loudly on at
// boot rather than on the first upload.
func New(cfg *config.Config, logger *slog.Logger, st *store.Store) (*http.Server, *asynq.Server, asynq.Handler, error) {
	authSvc := auth.NewService(st, logger, cfg)
	japaSvc := japa.NewService(st, logger)

	var videoStorage reels.VideoStorage
	var localStorage *reels.LocalVideoStorage
	switch cfg.VideoStorageBackend {
	case "local":
		local, err := reels.NewLocalVideoStorage(cfg.LocalUploadDir, cfg.PublicBaseURL)
		if err != nil {
			return nil, nil, nil, fmt.Errorf("set up local video storage: %w", err)
		}
		localStorage = local
		videoStorage = local
	case "cloudflare":
		// Not implemented yet (docs/TECH_STACK.md §3) — nothing to verify
		// it against without a real Cloudflare account and API token.
		// config.Load already rejects any other value, so this is the
		// only other case reachable.
		return nil, nil, nil, fmt.Errorf("VIDEO_STORAGE_BACKEND=cloudflare is not implemented yet")
	}

	redisOpt, err := asynq.ParseRedisURI(cfg.RedisURL)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("parse REDIS_URL for asynq: %w", err)
	}

	pipeline, err := moderation.BuildPipeline(cfg, logger)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("build moderation pipeline: %w", err)
	}
	workerServer, workerHandler := moderation.NewWorkerServer(redisOpt, st, pipeline, logger)
	enqueuer := moderation.NewAsynqEnqueuer(redisOpt)

	reelsSvc := reels.NewService(st, videoStorage, enqueuer, logger)
	moderationSvc := moderation.NewService(st)
	socialSvc := social.NewService(st)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", healthHandler(logger, st))
	mux.HandleFunc("POST /v1/auth/otp/request", requestOTPHandler(logger, authSvc))
	mux.HandleFunc("POST /v1/auth/otp/verify", verifyOTPHandler(logger, authSvc))
	mux.HandleFunc("POST /v1/auth/refresh", refreshTokenHandler(logger, authSvc))
	mux.Handle("GET /v1/me", requireAuth(authSvc)(meHandler()))
	mux.Handle("POST /v1/japa/taps", requireAuth(authSvc)(submitJapaTapsHandler(logger, japaSvc)))
	mux.Handle("GET /v1/japa/streak", requireAuth(authSvc)(japaStreakHandler(logger, japaSvc)))

	mux.Handle("POST /v1/reels/uploads",
		requireAuth(authSvc)(requireRole("creator")(createUploadTargetHandler(logger, reelsSvc))))
	mux.Handle("POST /v1/reels",
		requireAuth(authSvc)(requireRole("creator")(createReelHandler(logger, reelsSvc))))
	// optionalAuth, not requireAuth or no-auth-at-all — see listFeedHandler's
	// doc for why the feed still resolves claims when a token is present.
	mux.Handle("GET /v1/reels", optionalAuth(authSvc)(listFeedHandler(logger, reelsSvc, socialSvc)))

	// The P0 renamed interactions (docs/PRD.md §6/§7.2): Pranam, Smaran, and
	// Sevak are toggles; Prasad just records a share; Satsang read is public
	// like the feed itself (optionalAuth would add nothing here since
	// listSatsangHandler never uses viewer identity), write requires auth.
	mux.Handle("POST /v1/reels/{id}/pranam", requireAuth(authSvc)(pranamHandler(logger, socialSvc)))
	mux.Handle("POST /v1/reels/{id}/smaran", requireAuth(authSvc)(smaranHandler(logger, socialSvc)))
	mux.Handle("POST /v1/reels/{id}/prasad", requireAuth(authSvc)(prasadHandler(logger, socialSvc)))
	mux.Handle("POST /v1/reels/{id}/satsang", requireAuth(authSvc)(postSatsangHandler(logger, socialSvc)))
	mux.HandleFunc("GET /v1/reels/{id}/satsang", listSatsangHandler(logger, socialSvc))
	mux.Handle("POST /v1/users/{id}/sevak", requireAuth(authSvc)(sevakHandler(logger, socialSvc)))

	mux.Handle("POST /v1/reels/{id}/reports",
		requireAuth(authSvc)(submitReportHandler(logger, moderationSvc)))
	mux.Handle("GET /v1/moderation/reports",
		requireAuth(authSvc)(requireModerator(listModerationQueueHandler(logger, moderationSvc))))
	mux.Handle("POST /v1/moderation/reports/{id}/dismiss",
		requireAuth(authSvc)(requireModerator(dismissReportHandler(logger, moderationSvc))))
	mux.Handle("POST /v1/moderation/reports/{id}/remove-reel",
		requireAuth(authSvc)(requireModerator(removeReelHandler(logger, moderationSvc))))
	mux.Handle("GET /v1/moderation/audit-log",
		requireAuth(authSvc)(requireModerator(listAuditLogHandler(logger, moderationSvc))))

	if localStorage != nil {
		mux.HandleFunc("PUT /v1/reels/uploads/{id}/file", uploadLocalVideoHandler(logger, localStorage))
		mux.HandleFunc("GET /v1/reels/uploads/{id}/file", playLocalVideoHandler(logger, localStorage))
	}

	httpServer := &http.Server{
		Addr:    cfg.Addr,
		Handler: logRequests(logger)(mux),
	}
	return httpServer, workerServer, workerHandler, nil
}

// healthHandler pings Postgres and Redis on every call. Dependency error
// detail is logged server-side only — the response body just says which
// dependency failed, not the underlying error, since /healthz is reachable
// without auth and connection errors can leak DSN/network internals.
func healthHandler(logger *slog.Logger, st *store.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		pgErr, redisErr := st.HealthCheck(r.Context())

		deps := map[string]string{"postgres": "ok", "redis": "ok"}
		status := "ok"
		code := http.StatusOK

		if pgErr != nil {
			deps["postgres"] = "error"
			status = "degraded"
			code = http.StatusServiceUnavailable
			logger.Error("healthz: postgres unreachable", "error", pgErr)
		}
		if redisErr != nil {
			deps["redis"] = "error"
			status = "degraded"
			code = http.StatusServiceUnavailable
			logger.Error("healthz: redis unreachable", "error", redisErr)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(code)
		if err := json.NewEncoder(w).Encode(map[string]any{
			"status":       status,
			"dependencies": deps,
		}); err != nil {
			logger.Error("failed to write health response", "error", err)
		}
	}
}

func logRequests(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(rec, r)
			logger.Info("request", "method", r.Method, "path", r.URL.Path, "status", rec.status)
		})
	}
}

// statusRecorder captures the status code a handler writes, since
// http.ResponseWriter doesn't expose it after the fact and logRequests logs
// after the handler runs so it can report the outcome, not just the intent.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}
