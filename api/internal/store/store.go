// Package store manages the API's connections to Postgres and Redis.
package store

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// Store holds the live Postgres and Redis connections shared across the API.
type Store struct {
	PG    *pgxpool.Pool
	Redis *redis.Client
}

// Connect dials Postgres and Redis and pings both before returning, so the
// process fails fast at startup rather than serving traffic against a
// backend it can't actually reach. pgxpool.New itself only parses the DSN
// and connects lazily, hence the explicit Ping.
func Connect(ctx context.Context, databaseURL, redisURL string) (*Store, error) {
	pgPool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("postgres: %w", err)
	}
	if err := pgPool.Ping(ctx); err != nil {
		pgPool.Close()
		return nil, fmt.Errorf("postgres: %w", err)
	}

	redisOpts, err := redis.ParseURL(redisURL)
	if err != nil {
		pgPool.Close()
		return nil, fmt.Errorf("redis: parse url: %w", err)
	}
	redisClient := redis.NewClient(redisOpts)
	if err := redisClient.Ping(ctx).Err(); err != nil {
		pgPool.Close()
		redisClient.Close()
		return nil, fmt.Errorf("redis: %w", err)
	}

	return &Store{PG: pgPool, Redis: redisClient}, nil
}

// Close releases both connections. Safe to call once during shutdown.
func (s *Store) Close() {
	s.PG.Close()
	s.Redis.Close()
}

// HealthCheck pings Postgres and Redis independently and returns each
// dependency's error (nil on success) so callers can report per-dependency
// status rather than a single pass/fail bit.
func (s *Store) HealthCheck(ctx context.Context) (pgErr, redisErr error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	pgErr = s.PG.Ping(ctx)
	redisErr = s.Redis.Ping(ctx).Err()
	return pgErr, redisErr
}
