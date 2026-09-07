// Command seedaudio populates the seeded audio library (docs/PRD.md §7.3
// P0, IMPLEMENTATION_PLAN.md Phase 3) from local source recordings — the
// mechanism that solves the cold-start problem: a brand-new creator can
// sing over a tanpura drone and post within 30 seconds, instead of needing
// a complete original recording before their first upload.
//
// Reads seed_audio/manifest.json (resolved relative to this source file,
// same trick cmd/migrate uses for db/migrations, so `go run ./cmd/seedaudio`
// works the same regardless of invocation directory) and, for each entry
// whose audio file actually exists on disk, copies it into local platform
// audio storage and inserts or updates its audio_library row. An entry
// whose file hasn't been recorded/sourced yet is skipped with a warning,
// not a fatal error — the manifest can list the full target set (~50
// tracks per the Phase 3 plan) before every recording exists, and get
// filled in incrementally by re-running this command.
//
// Every seeded track bypasses the three-layer moderation pipeline entirely
// (internal/moderation) and gets no artist row (internal/audio.Service's
// own doc on SeedPlatformTrack explains why) — this command is the only
// thing that ever calls SeedPlatformTrack, and it's meant to be run by a
// developer against recordings they themselves sourced or made, the same
// trust boundary a reel upload's moderation pipeline exists to substitute
// for when the uploader is an arbitrary member of the public instead.
//
// Usage:
//
//	go run ./cmd/seedaudio
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"github.com/anhad/api/internal/audio"
	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/store"
)

// manifestEntry is one row of seed_audio/manifest.json. Category defaults
// to "meditation_naad" when empty — docs/PRD.md §4.1 names that category
// explicitly as "(instrumental/ambient, for the audio library)", which is
// exactly what every track this command seeds is; the field still exists
// per-entry rather than being hardcoded so a future seeded track that
// genuinely belongs elsewhere (a sung Gayatri Mantra loop, say) isn't
// forced into the wrong category just because this command only ever wrote
// one value before.
type manifestEntry struct {
	File     string  `json:"file"`
	Title    string  `json:"title"`
	Category string  `json:"category,omitempty"`
	Deity    *string `json:"deity,omitempty"`
	Raga     *string `json:"raga,omitempty"`
}

func seedAudioDir() string {
	_, thisFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "seed_audio")
}

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))

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

	storage, err := audio.NewLocalPlatformAudioStorage(cfg.LocalPlatformAudioDir, cfg.PublicBaseURL)
	if err != nil {
		logger.Error("failed to set up local platform audio storage", "error", err)
		os.Exit(1)
	}
	audioSvc := audio.NewService(st, audio.NewLocalAudioSource())

	dir := seedAudioDir()
	manifestPath := filepath.Join(dir, "manifest.json")
	raw, err := os.ReadFile(manifestPath)
	if err != nil {
		logger.Error("failed to read manifest", "path", manifestPath, "error", err)
		os.Exit(1)
	}
	var entries []manifestEntry
	if err := json.Unmarshal(raw, &entries); err != nil {
		logger.Error("failed to parse manifest", "path", manifestPath, "error", err)
		os.Exit(1)
	}

	var created, updated, skipped, failed int
	for _, entry := range entries {
		filePath := filepath.Join(dir, entry.File)
		if _, err := os.Stat(filePath); err != nil {
			logger.Warn("skipping manifest entry: audio file not found yet",
				"title", entry.Title, "expected_path", filePath)
			skipped++
			continue
		}

		category := entry.Category
		if category == "" {
			category = "meditation_naad"
		}

		audioURL, err := storage.Ingest(filePath)
		if err != nil {
			logger.Error("failed to ingest audio file", "title", entry.Title, "error", err)
			failed++
			continue
		}

		id, wasCreated, err := audioSvc.SeedPlatformTrack(
			context.Background(), category, entry.Title, audioURL, entry.Deity, entry.Raga,
		)
		if err != nil {
			logger.Error("failed to seed platform track", "title", entry.Title, "error", err)
			failed++
			continue
		}

		if wasCreated {
			created++
			logger.Info("created platform track", "id", id, "title", entry.Title)
		} else {
			updated++
			logger.Info("updated platform track", "id", id, "title", entry.Title)
		}
	}

	logger.Info("seed complete",
		"created", created, "updated", updated, "skipped_missing_file", skipped, "failed", failed,
		"total_in_manifest", len(entries))
	if failed > 0 {
		os.Exit(1)
	}
}
