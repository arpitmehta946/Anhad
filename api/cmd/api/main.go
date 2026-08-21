// Command api is the entrypoint for the Anhad backend API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/server"
	"github.com/anhad/api/internal/store"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg, err := config.Load()
	if err != nil {
		logger.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	connectCtx, connectCancel := context.WithTimeout(context.Background(), 10*time.Second)
	st, err := store.Connect(connectCtx, cfg.DatabaseURL, cfg.RedisURL)
	connectCancel()
	if err != nil {
		logger.Error("failed to connect to datastores", "error", err)
		os.Exit(1)
	}
	defer st.Close()

	srv, worker, workerHandler, err := server.New(cfg, logger, st)
	if err != nil {
		logger.Error("failed to build server", "error", err)
		os.Exit(1)
	}

	go func() {
		logger.Info("starting server", "addr", cfg.Addr, "env", cfg.Env)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	// The moderation pipeline worker (internal/moderation) runs embedded in
	// this same process — see server.New's doc for why that's fine at this
	// project's current scale rather than a separate deployment.
	go func() {
		logger.Info("starting moderation worker")
		if err := worker.Run(workerHandler); err != nil {
			logger.Error("moderation worker error", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	logger.Info("shutting down")
	worker.Shutdown()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
	}
}
