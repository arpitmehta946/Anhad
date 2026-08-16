// Command migrate applies or rolls back the SQL migrations in
// /db/migrations against the database at DATABASE_URL.
//
// Usage:
//
//	go run ./cmd/migrate up          # apply all pending migrations
//	go run ./cmd/migrate down        # roll back one migration
//	go run ./cmd/migrate down 3      # roll back three migrations
//	go run ./cmd/migrate version     # print the current schema version
package main

import (
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"strconv"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/anhad/api/internal/config"
)

// migrationsDir resolves db/migrations relative to this source file rather
// than the process's working directory, so `go run ./cmd/migrate` behaves
// the same whether it's invoked from the repo root or from api/.
func migrationsDir() string {
	_, thisFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "..", "db", "migrations")
}

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))

	if len(os.Args) < 2 {
		logger.Error("usage: migrate <up|down|version> [steps]")
		os.Exit(1)
	}
	cmd := os.Args[1]

	cfg, err := config.Load()
	if err != nil {
		logger.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	db, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		logger.Error("failed to open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	driver, err := postgres.WithInstance(db, &postgres.Config{})
	if err != nil {
		logger.Error("failed to init postgres driver", "error", err)
		os.Exit(1)
	}

	dir := migrationsDir()
	m, err := migrate.NewWithDatabaseInstance("file://"+filepath.ToSlash(dir), "postgres", driver)
	if err != nil {
		logger.Error("failed to init migrator", "error", err, "path", dir)
		os.Exit(1)
	}

	switch cmd {
	case "up":
		err = m.Up()
	case "down":
		steps := 1
		if len(os.Args) > 2 {
			steps, err = strconv.Atoi(os.Args[2])
			if err != nil {
				logger.Error("invalid step count", "arg", os.Args[2])
				os.Exit(1)
			}
		}
		err = m.Steps(-steps)
	case "version":
		version, dirty, verr := m.Version()
		if verr != nil {
			logger.Error("failed to read version", "error", verr)
			os.Exit(1)
		}
		fmt.Printf("version=%d dirty=%t\n", version, dirty)
		return
	default:
		logger.Error("unknown command", "command", cmd, "usage", "up|down|version")
		os.Exit(1)
	}

	if err != nil && !errors.Is(err, migrate.ErrNoChange) {
		logger.Error("migration failed", "command", cmd, "error", err)
		os.Exit(1)
	}

	version, dirty, err := m.Version()
	if err != nil && !errors.Is(err, migrate.ErrNilVersion) {
		logger.Error("failed to read resulting version", "error", err)
		os.Exit(1)
	}
	logger.Info("migration complete", "command", cmd, "version", version, "dirty", dirty)
}
