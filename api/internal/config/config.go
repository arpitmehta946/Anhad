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
	// PublicBaseURL is how a client reaches this API — used to build
	// absolute URLs for the local video-storage stub's own upload/playback
	// routes (internal/reels). Matches whatever API_BASE_URL the mobile
	// app is already configured with (mobile/lib/src/config.dart), since
	// those URLs need to be reachable from the same device the app runs
	// on, not just from this process itself.
	PublicBaseURL string
	// LocalUploadDir is where the local video-storage stub writes
	// uploaded files when VideoStorageBackend is "local" — unused
	// otherwise.
	LocalUploadDir string
	// VideoStorageBackend selects where reel video actually lives: "local"
	// (default — a disk-backed stand-in for Cloudflare Stream, so the
	// upload/feed flow can be built and tested with no Cloudflare account)
	// or "cloudflare" (TECH_STACK.md §3's real, eventual backend — not yet
	// implemented; see internal/reels/storage.go).
	VideoStorageBackend string

	// The three-layer moderation pipeline (docs/PRD.md §8.1,
	// internal/moderation). Each layer is a separate backend switch, same
	// shape as VideoStorageBackend, because each needs a different (or no)
	// external account and the three shouldn't be coupled to one flag.

	// FFmpegPath is the ffmpeg binary used to pull an audio track out of an
	// uploaded video before either transcription or fingerprinting touches
	// it. No account, just needs installing.
	FFmpegPath string

	// TranscriberBackend: "local" (default — self-hosted whisper.cpp, free,
	// no account) or "openai" (Whisper API, needs OpenAIAPIKey). Swapping
	// is this one flag, not a rewrite — see internal/moderation/
	// transcriber.go.
	TranscriberBackend string
	WhisperCliPath     string // TranscriberBackend=local
	WhisperModelPath   string // TranscriberBackend=local
	OpenAIAPIKey       string // TranscriberBackend=openai

	// ClassifierBackend: "keyword" (default — a crude heuristic, dev
	// plumbing only; PRD.md §8.1 is explicit that a keyword list alone
	// cannot make this judgment for real), "claude" (needs
	// AnthropicAPIKey), or "gemini" (needs GeminiAPIKey — the option that
	// actually works from India today, since Anthropic's API doesn't
	// accept Indian payment methods and Gemini has a usable free tier).
	// claude and gemini share the exact same prompt
	// (classifier_claude.go's classifierSystemPrompt) so results stay
	// comparable across backends. The one layer of the three that has no
	// honest free stand-in — see internal/moderation/classifier.go.
	ClassifierBackend string
	AnthropicAPIKey   string
	AnthropicModel    string
	GeminiAPIKey      string
	GeminiModel       string

	// FingerprintBackend: "none" (default — always reports no match; there
	// is no free, reliable commercial-catalog fingerprint DB to stub
	// against) or "acrcloud" (needs the ACRCloud* fields — not implemented
	// yet, matches VideoStorageBackend=cloudflare's own "not implemented"
	// stance until there's a real account to build and verify it against).
	FingerprintBackend string
	ACRCloudHost       string
	ACRCloudAccessKey  string
	ACRCloudSecretKey  string
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
		PublicBaseURL:       getenv("PUBLIC_BASE_URL", "http://localhost:8080"),
		LocalUploadDir:      getenv("LOCAL_UPLOAD_DIR", "./data/uploads"),
		VideoStorageBackend: getenv("VIDEO_STORAGE_BACKEND", "local"),

		FFmpegPath: getenv("FFMPEG_PATH", "ffmpeg"),

		TranscriberBackend: getenv("TRANSCRIBER_BACKEND", "local"),
		WhisperCliPath:     getenv("WHISPER_CLI_PATH", "whisper-cli"),
		WhisperModelPath:   getenv("WHISPER_MODEL_PATH", ""),
		OpenAIAPIKey:       getenv("OPENAI_API_KEY", ""),

		ClassifierBackend: getenv("CLASSIFIER_BACKEND", "keyword"),
		AnthropicAPIKey:   getenv("ANTHROPIC_API_KEY", ""),
		AnthropicModel:    getenv("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001"),
		GeminiAPIKey:      getenv("GEMINI_API_KEY", ""),
		GeminiModel:       getenv("GEMINI_MODEL", "gemini-3.6-flash"),

		FingerprintBackend: getenv("FINGERPRINT_BACKEND", "none"),
		ACRCloudHost:       getenv("ACRCLOUD_HOST", ""),
		ACRCloudAccessKey:  getenv("ACRCLOUD_ACCESS_KEY", ""),
		ACRCloudSecretKey:  getenv("ACRCLOUD_SECRET_KEY", ""),
	}

	if cfg.Addr == "" {
		return nil, fmt.Errorf("API_ADDR must not be empty")
	}
	if cfg.Env != "development" && cfg.JWTSecret == "dev-insecure-jwt-secret-change-me" {
		return nil, fmt.Errorf("JWT_SECRET must be set explicitly outside development")
	}
	if cfg.VideoStorageBackend != "local" && cfg.VideoStorageBackend != "cloudflare" {
		return nil, fmt.Errorf("VIDEO_STORAGE_BACKEND must be \"local\" or \"cloudflare\", got %q", cfg.VideoStorageBackend)
	}

	// TRANSCRIBER_BACKEND=local's own required field (WHISPER_MODEL_PATH)
	// is deliberately NOT checked here, unlike the claude/acrcloud checks
	// below — "local" is this flag's default, and config.Load is shared by
	// cmd/migrate and other commands that never touch the moderation
	// pipeline at all. Failing here would break "go run ./cmd/migrate
	// works with zero setup" for a field only cmd/api's moderation worker
	// actually needs; internal/moderation.BuildPipeline checks it instead,
	// so only the command that actually builds the pipeline can fail on it.
	if cfg.TranscriberBackend != "local" && cfg.TranscriberBackend != "openai" {
		return nil, fmt.Errorf("TRANSCRIBER_BACKEND must be \"local\" or \"openai\", got %q", cfg.TranscriberBackend)
	}
	if cfg.TranscriberBackend == "openai" && cfg.OpenAIAPIKey == "" {
		return nil, fmt.Errorf("OPENAI_API_KEY must be set when TRANSCRIBER_BACKEND=openai")
	}

	switch cfg.ClassifierBackend {
	case "keyword":
	case "claude":
		if cfg.AnthropicAPIKey == "" {
			return nil, fmt.Errorf("ANTHROPIC_API_KEY must be set when CLASSIFIER_BACKEND=claude")
		}
	case "gemini":
		if cfg.GeminiAPIKey == "" {
			return nil, fmt.Errorf("GEMINI_API_KEY must be set when CLASSIFIER_BACKEND=gemini")
		}
	default:
		return nil, fmt.Errorf("CLASSIFIER_BACKEND must be \"keyword\", \"claude\", or \"gemini\", got %q", cfg.ClassifierBackend)
	}

	switch cfg.FingerprintBackend {
	case "none":
	case "acrcloud":
		return nil, fmt.Errorf("FINGERPRINT_BACKEND=acrcloud is not implemented yet")
	default:
		return nil, fmt.Errorf("FINGERPRINT_BACKEND must be \"none\" or \"acrcloud\", got %q", cfg.FingerprintBackend)
	}

	return cfg, nil
}

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
