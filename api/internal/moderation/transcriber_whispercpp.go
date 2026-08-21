package moderation

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// WhisperCppTranscriber shells out to a local whisper.cpp `whisper-cli`
// binary — free, no account, runs on CPU (docs/TECH_STACK.md §implementation,
// PRD.md §8.1). This is the default Transcriber; OpenAIWhisperTranscriber
// (transcriber_openai.go) is the config-switch alternative if local
// accuracy on sung Hindi/Sanskrit turns out too weak.
type WhisperCppTranscriber struct {
	CliPath   string
	ModelPath string
}

func NewWhisperCppTranscriber(cliPath, modelPath string) *WhisperCppTranscriber {
	return &WhisperCppTranscriber{CliPath: cliPath, ModelPath: modelPath}
}

// whisperCliOutput mirrors just the fields of whisper-cli's -oj JSON output
// this package actually reads.
type whisperCliOutput struct {
	Result struct {
		Language string `json:"language"`
	} `json:"result"`
	Transcription []struct {
		Text string `json:"text"`
	} `json:"transcription"`
}

func (t *WhisperCppTranscriber) Transcribe(ctx context.Context, wavPath string) (*Transcript, error) {
	outBase, err := os.CreateTemp("", "anhad-whisper-out-*")
	if err != nil {
		return nil, fmt.Errorf("create temp output base: %w", err)
	}
	outBasePath := outBase.Name()
	outBase.Close()
	os.Remove(outBasePath) // whisper-cli writes outBasePath+".json" itself
	defer os.Remove(outBasePath + ".json")

	cmd := exec.CommandContext(ctx, t.CliPath,
		"-m", t.ModelPath,
		"-f", wavPath,
		"-l", "auto", // auto-detect — this platform's audio spans Hindi, Sanskrit, and other languages
		"-oj", // JSON output — structured language + segments, no log-scraping
		"-of", outBasePath,
		"-np", // suppress whisper.cpp's own log banner on stdout
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("whisper-cli: %w: %s", err, truncate(string(output), 2000))
	}

	raw, err := os.ReadFile(outBasePath + ".json")
	if err != nil {
		return nil, fmt.Errorf("read whisper-cli output: %w", err)
	}
	var parsed whisperCliOutput
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, fmt.Errorf("parse whisper-cli output: %w", err)
	}

	segments := make([]string, 0, len(parsed.Transcription))
	for _, seg := range parsed.Transcription {
		if s := strings.TrimSpace(seg.Text); s != "" {
			segments = append(segments, s)
		}
	}
	return &Transcript{
		Text:     strings.Join(segments, " "),
		Language: parsed.Result.Language,
	}, nil
}

var _ Transcriber = (*WhisperCppTranscriber)(nil)

// checkWhisperCliAvailable is a startup sanity check — cheap insurance
// against a misconfigured WHISPER_CLI_PATH failing loudly on the first
// real upload instead of at boot.
func checkWhisperCliAvailable(cliPath string) error {
	if _, err := exec.LookPath(cliPath); err != nil {
		if _, statErr := os.Stat(cliPath); statErr != nil {
			return fmt.Errorf("whisper-cli not found at %q: %w", cliPath, err)
		}
	}
	return nil
}
