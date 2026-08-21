package moderation

import (
	"fmt"
	"log/slog"

	"github.com/anhad/api/internal/config"
)

// BuildPipeline assembles the real Pipeline from config — the one place
// TranscriberBackend/ClassifierBackend/FingerprintBackend actually get
// switched on, mirroring server.New's own VideoStorageBackend switch in
// api/internal/server/server.go. config.Load has already validated these
// combinations (e.g. a claude backend without ANTHROPIC_API_KEY never
// reaches here), so this only needs to construct, not re-validate.
func BuildPipeline(cfg *config.Config, logger *slog.Logger) (*Pipeline, error) {
	var transcriber Transcriber
	switch cfg.TranscriberBackend {
	case "local":
		// Unlike the claude/acrcloud checks below, this can't live in
		// config.Load — see its own comment on why. Checked here instead,
		// so only a command that actually builds the pipeline (cmd/api)
		// ever fails on it.
		if cfg.WhisperModelPath == "" {
			return nil, fmt.Errorf("WHISPER_MODEL_PATH must be set when TRANSCRIBER_BACKEND=local")
		}
		if err := checkWhisperCliAvailable(cfg.WhisperCliPath); err != nil {
			return nil, fmt.Errorf("whisper.cpp not available: %w", err)
		}
		transcriber = NewWhisperCppTranscriber(cfg.WhisperCliPath, cfg.WhisperModelPath)
	case "openai":
		transcriber = NewOpenAIWhisperTranscriber(cfg.OpenAIAPIKey)
	}

	var classifier IntentClassifier
	switch cfg.ClassifierBackend {
	case "keyword":
		classifier = NewKeywordClassifier()
	case "claude":
		classifier = NewClaudeClassifier(cfg.AnthropicAPIKey, cfg.AnthropicModel)
	case "gemini":
		classifier = NewGeminiClassifier(cfg.GeminiAPIKey, cfg.GeminiModel)
	}

	var fingerprint FingerprintChecker
	switch cfg.FingerprintBackend {
	case "none":
		fingerprint = NewNoMatchFingerprintChecker()
	}
	// "acrcloud" is rejected by config.Load before this ever runs.

	return &Pipeline{
		FFmpegPath:  cfg.FFmpegPath,
		Transcriber: transcriber,
		Classifier:  classifier,
		Fingerprint: fingerprint,
		Logger:      logger,
	}, nil
}
