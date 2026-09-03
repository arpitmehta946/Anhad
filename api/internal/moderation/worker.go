package moderation

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/hibiken/asynq"

	"github.com/anhad/api/internal/store"
)

// TaskClassifyReel is the one Asynq task type this package's worker
// handles — docs/TECH_STACK.md's documented job-queue choice ("Asynq for
// Go") for the moderation pipeline specifically. Run embedded in the same
// process as the API server (see cmd/api/main.go) rather than a separate
// binary/deployment: this project has no separate worker infra yet, and
// Asynq's client and server share one Redis connection either way — the
// separation that matters (uploads return instantly, the pipeline runs
// after) is about the queue, not about which OS process happens to drain
// it.
const TaskClassifyReel = "moderation:classify_reel"

type classifyReelPayload struct {
	ReelID   string `json:"reel_id"`
	VideoURL string `json:"video_url"`
}

// Enqueuer is the narrow interface internal/reels depends on to kick off
// moderation after a reel is created — reels.Service takes one of these
// rather than importing this package directly or talking to Asynq itself,
// the same shape as its existing VideoStorage dependency.
type Enqueuer interface {
	EnqueueClassifyReel(ctx context.Context, reelID, videoURL string) error
}

// AsynqEnqueuer is the real Enqueuer, backed by an *asynq.Client.
type AsynqEnqueuer struct {
	Client *asynq.Client
}

func NewAsynqEnqueuer(redisOpt asynq.RedisConnOpt) *AsynqEnqueuer {
	return &AsynqEnqueuer{Client: asynq.NewClient(redisOpt)}
}

func (e *AsynqEnqueuer) EnqueueClassifyReel(ctx context.Context, reelID, videoURL string) error {
	payload, err := json.Marshal(classifyReelPayload{ReelID: reelID, VideoURL: videoURL})
	if err != nil {
		return fmt.Errorf("marshal classify-reel payload: %w", err)
	}
	task := asynq.NewTask(TaskClassifyReel, payload)
	if _, err := e.Client.EnqueueContext(ctx, task); err != nil {
		return fmt.Errorf("enqueue classify-reel task: %w", err)
	}
	return nil
}

// NewWorkerServer builds the Asynq server + handler that drains
// TaskClassifyReel. Asynq takes the handler as an argument to Start/Run
// rather than attaching it to the server itself, so both come back
// together — cmd/api/main.go calls server.Start(handler) alongside the
// HTTP server and server.Shutdown() on the same signal that stops it.
func NewWorkerServer(redisOpt asynq.RedisConnOpt, st *store.Store, pipeline *Pipeline, audioLib AudioLibrary, logger *slog.Logger) (*asynq.Server, asynq.Handler) {
	server := asynq.NewServer(redisOpt, asynq.Config{
		Concurrency: 2, // CPU-bound (whisper.cpp) — more than a couple in parallel just contends for the same cores
		Logger:      slogAdapter{logger},
	})

	mux := asynq.NewServeMux()
	mux.HandleFunc(TaskClassifyReel, func(ctx context.Context, t *asynq.Task) error {
		var payload classifyReelPayload
		if err := json.Unmarshal(t.Payload(), &payload); err != nil {
			return fmt.Errorf("unmarshal classify-reel payload: %w", err)
		}
		return RunAndSave(ctx, st, pipeline, audioLib, payload.ReelID, payload.VideoURL)
	})

	return server, mux
}

// slogAdapter satisfies asynq.Logger with this project's existing
// *slog.Logger rather than pulling in Asynq's own logging setup.
type slogAdapter struct{ logger *slog.Logger }

func (a slogAdapter) Debug(args ...interface{}) { a.logger.Debug(fmt.Sprint(args...)) }
func (a slogAdapter) Info(args ...interface{})  { a.logger.Info(fmt.Sprint(args...)) }
func (a slogAdapter) Warn(args ...interface{})  { a.logger.Warn(fmt.Sprint(args...)) }
func (a slogAdapter) Error(args ...interface{}) { a.logger.Error(fmt.Sprint(args...)) }
func (a slogAdapter) Fatal(args ...interface{}) { a.logger.Error(fmt.Sprint(args...)) }
