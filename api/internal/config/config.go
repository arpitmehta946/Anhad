// Package config loads runtime configuration from the environment.
package config

import (
	"fmt"
	"os"
)

// Config holds all environment-derived settings for the API process.
type Config struct {
	Addr        string
	Env         string
	DatabaseURL string
	RedisURL    string
}

// Load reads configuration from environment variables, applying local-dev
// defaults that match docker-compose.yml so `go run` works with zero setup.
func Load() (*Config, error) {
	cfg := &Config{
		Addr:        getenv("API_ADDR", ":8080"),
		Env:         getenv("APP_ENV", "development"),
		DatabaseURL: getenv("DATABASE_URL", "postgres://anhad:anhad@localhost:5432/anhad?sslmode=disable"),
		RedisURL:    getenv("REDIS_URL", "redis://localhost:6379/0"),
	}

	if cfg.Addr == "" {
		return nil, fmt.Errorf("API_ADDR must not be empty")
	}

	return cfg, nil
}

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
