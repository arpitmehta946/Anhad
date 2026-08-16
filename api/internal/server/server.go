// Package server builds the HTTP server and top-level route table.
package server

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/store"
)

// New assembles an *http.Server with the Phase 0 route table. Feed, auth,
// japa, and moderation routes land in later phases per IMPLEMENTATION_PLAN.md.
func New(cfg *config.Config, logger *slog.Logger, st *store.Store) *http.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", healthHandler(logger, st))

	return &http.Server{
		Addr:    cfg.Addr,
		Handler: logRequests(logger)(mux),
	}
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
			logger.Info("request", "method", r.Method, "path", r.URL.Path)
			next.ServeHTTP(w, r)
		})
	}
}
