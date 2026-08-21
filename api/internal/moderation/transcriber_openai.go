package moderation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
)

// OpenAIWhisperTranscriber calls OpenAI's hosted Whisper API instead of
// running locally — TRANSCRIBER_BACKEND=openai, needs OPENAI_API_KEY. The
// config switch this exists for: if WhisperCppTranscriber's accuracy on
// sung Hindi/Sanskrit turns out too weak against testdata/, moving here is
// one env var, not a rewrite — both implement the same Transcriber
// interface and the pipeline (pipeline.go) never branches on which one is
// live.
type OpenAIWhisperTranscriber struct {
	APIKey string
	Client *http.Client
}

func NewOpenAIWhisperTranscriber(apiKey string) *OpenAIWhisperTranscriber {
	return &OpenAIWhisperTranscriber{APIKey: apiKey, Client: http.DefaultClient}
}

type openAITranscriptionResponse struct {
	Text     string `json:"text"`
	Language string `json:"language"`
}

func (t *OpenAIWhisperTranscriber) Transcribe(ctx context.Context, wavPath string) (*Transcript, error) {
	f, err := os.Open(wavPath)
	if err != nil {
		return nil, fmt.Errorf("open wav: %w", err)
	}
	defer f.Close()

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("file", filepath.Base(wavPath))
	if err != nil {
		return nil, fmt.Errorf("create multipart file field: %w", err)
	}
	if _, err := io.Copy(part, f); err != nil {
		return nil, fmt.Errorf("copy wav into request: %w", err)
	}
	if err := writer.WriteField("model", "whisper-1"); err != nil {
		return nil, fmt.Errorf("write model field: %w", err)
	}
	if err := writer.WriteField("response_format", "verbose_json"); err != nil {
		return nil, fmt.Errorf("write response_format field: %w", err)
	}
	if err := writer.Close(); err != nil {
		return nil, fmt.Errorf("close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.openai.com/v1/audio/transcriptions", &body)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+t.APIKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := t.Client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call openai whisper api: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read openai whisper response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai whisper api returned %d: %s", resp.StatusCode, truncate(string(respBody), 1000))
	}

	var parsed openAITranscriptionResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("parse openai whisper response: %w", err)
	}
	return &Transcript{Text: parsed.Text, Language: parsed.Language}, nil
}

var _ Transcriber = (*OpenAIWhisperTranscriber)(nil)
