package moderation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// GeminiClassifier is the same real intent-judgment layer as
// ClaudeClassifier, against Google's Gemini API instead — CLASSIFIER_BACKEND
// =gemini, needs GEMINI_API_KEY. Exists because Anthropic's API doesn't
// accept Indian payment methods; Gemini's free tier does. Uses the exact
// same classifierSystemPrompt (classifier_claude.go) so results from the
// two backends stay comparable — this is a different HTTP call shape to
// the same judgment call, not a different judgment.
type GeminiClassifier struct {
	APIKey string
	Model  string
	Client *http.Client
}

func NewGeminiClassifier(apiKey, model string) *GeminiClassifier {
	return &GeminiClassifier{APIKey: apiKey, Model: model, Client: http.DefaultClient}
}

type geminiRequest struct {
	SystemInstruction geminiContent          `json:"systemInstruction"`
	Contents          []geminiContent        `json:"contents"`
	GenerationConfig  geminiGenerationConfig `json:"generationConfig"`
}

type geminiContent struct {
	Role  string       `json:"role,omitempty"`
	Parts []geminiPart `json:"parts"`
}

type geminiPart struct {
	Text string `json:"text"`
}

type geminiGenerationConfig struct {
	// Gemini can be asked to force valid JSON output directly, which is
	// more reliable than trusting the model to follow a "respond with only
	// JSON" instruction unenforced — parseVerdictJSON's markdown-fence
	// stripping stays as a defensive fallback either way.
	ResponseMimeType string `json:"responseMimeType"`
}

type geminiResponse struct {
	Candidates []struct {
		Content geminiContent `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// geminiMaxRetries/retryAfterPattern handle the free tier's request-per-
// minute cap (5 rpm as of this writing) — Gemini's 429 response spells out
// exactly how long to wait ("Please retry in 26.8s"), so retrying is just
// honoring that rather than guessing a backoff. A fixed pace (e.g.
// concurrency=1 with a manual sleep) would either be slower than
// necessary or still occasionally race the limit; parsing the actual
// hint adapts to whatever the account's real quota is.
const geminiMaxRetries = 5

var retryAfterPattern = regexp.MustCompile(`retry in ([\d.]+)s`)

func (c *GeminiClassifier) Classify(ctx context.Context, transcript string) (*ClassifierVerdict, error) {
	trimmed := strings.TrimSpace(transcript)
	if trimmed == "" {
		return &ClassifierVerdict{
			Label:  LabelUncertain,
			Reason: "no transcript text to judge (likely instrumental or inaudible)",
		}, nil
	}

	var lastErr error
	for attempt := 0; attempt <= geminiMaxRetries; attempt++ {
		verdict, retryAfter, err := c.classifyOnce(ctx, trimmed)
		if err == nil {
			return verdict, nil
		}
		lastErr = err
		if retryAfter <= 0 {
			return nil, err // not a rate-limit error — no point retrying
		}
		select {
		case <-time.After(retryAfter):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return nil, fmt.Errorf("gave up after %d rate-limit retries: %w", geminiMaxRetries, lastErr)
}

// classifyOnce makes a single attempt. retryAfter is >0 only for a 429 the
// caller should retry after waiting; any other error (including a
// non-rate-limit 4xx/5xx) returns retryAfter == 0 so Classify doesn't
// retry something retrying won't fix.
func (c *GeminiClassifier) classifyOnce(ctx context.Context, trimmed string) (*ClassifierVerdict, time.Duration, error) {
	reqBody := geminiRequest{
		SystemInstruction: geminiContent{Parts: []geminiPart{{Text: classifierSystemPrompt}}},
		Contents: []geminiContent{
			{Role: "user", Parts: []geminiPart{{Text: "Transcript:\n\n" + trimmed}}},
		},
		GenerationConfig: geminiGenerationConfig{ResponseMimeType: "application/json"},
	}
	payload, err := json.Marshal(reqBody)
	if err != nil {
		return nil, 0, fmt.Errorf("marshal request: %w", err)
	}

	endpoint := fmt.Sprintf(
		"https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
		url.PathEscape(c.Model), url.QueryEscape(c.APIKey),
	)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, 0, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("call gemini api: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, 0, fmt.Errorf("read gemini response: %w", err)
	}

	var parsed geminiResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, 0, fmt.Errorf("parse gemini response: %w: %s", err, truncate(string(respBody), 500))
	}
	if resp.StatusCode != http.StatusOK {
		msg := string(respBody)
		if parsed.Error != nil {
			msg = parsed.Error.Message
		}
		if resp.StatusCode == http.StatusTooManyRequests {
			return nil, parseRetryAfter(msg), fmt.Errorf("gemini api returned 429: %s", msg)
		}
		return nil, 0, fmt.Errorf("gemini api returned %d: %s", resp.StatusCode, msg)
	}
	if len(parsed.Candidates) == 0 || len(parsed.Candidates[0].Content.Parts) == 0 {
		return nil, 0, fmt.Errorf("gemini response had no content")
	}

	verdict, err := parseVerdictJSON(parsed.Candidates[0].Content.Parts[0].Text)
	return verdict, 0, err
}

// parseRetryAfter pulls the delay out of Gemini's own "Please retry in
// 26.8s" message text. Falls back to a flat 20s (comfortably over the
// free tier's 60s/5-request window divided across a few retries) if the
// message shape ever changes and the pattern doesn't match — retrying at
// all is what matters; the exact wait is a minor efficiency question.
func parseRetryAfter(message string) time.Duration {
	m := retryAfterPattern.FindStringSubmatch(message)
	if m == nil {
		return 20 * time.Second
	}
	seconds, err := strconv.ParseFloat(m[1], 64)
	if err != nil || seconds <= 0 {
		return 20 * time.Second
	}
	// A small margin on top of the server's own estimate — retrying at
	// exactly T can still race the window boundary.
	return time.Duration(seconds*float64(time.Second)) + 2*time.Second
}

var _ IntentClassifier = (*GeminiClassifier)(nil)
