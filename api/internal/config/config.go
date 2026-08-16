// Package config loads runtime configuration from the environment.
package config

import (
	"fmt"
	"os"
)

// Config holds all environment-derived settings for the API process.
type Config struct {
	Addr                string
	Env                 string
	DatabaseURL         string
	RedisURL            string
	JWTSecret           string
	BootstrapAdminPhone string
}

// Load reads configuration from environment variables, applying local-dev
// defaults that match docker-compose.yml so `go run` works with zero setup.
func Load() (*Config, error) {
	cfg := &Config{
		Addr:        getenv("API_ADDR", ":8080"),
		Env:         getenv("APP_ENV", "development"),
		DatabaseURL: getenv("DATABASE_URL", "postgres://anhad:anhad@localhost:5432/anhad?sslmode=disable"),
		RedisURL:    getenv("REDIS_URL", "redis://localhost:6379/0"),
		// Dev-only fallback so `go run` works with zero setup, matching the
		// other local-dev defaults above. Every non-development environment
		// must set a real JWT_SECRET explicitly.
		JWTSecret: getenv("JWT_SECRET", "dev-insecure-jwt-secret-change-me"),
		// The first-admin bootstrap (docs/GAPS.md "Roles & permissions"):
		// whichever phone number this names gets role = admin the moment it
		// signs up, since nothing else can grant that role before an admin
		// already exists. Empty by default — the mechanism is a no-op until
		// explicitly configured.
		BootstrapAdminPhone: getenv("BOOTSTRAP_ADMIN_PHONE", ""),
	}

	if cfg.Addr == "" {
		return nil, fmt.Errorf("API_ADDR must not be empty")
	}
	if cfg.Env != "development" && cfg.JWTSecret == "dev-insecure-jwt-secret-change-me" {
		return nil, fmt.Errorf("JWT_SECRET must be set explicitly outside development")
	}

	return cfg, nil
}

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
