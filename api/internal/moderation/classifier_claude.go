package moderation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// ClaudeClassifier is the real intent-judgment layer docs/PRD.md §8.1
// calls for: "An LLM — e.g. Claude or a comparably capable model via API —
// is well suited to this specific judgment call; a keyword blocklist
// alone will not work." CLASSIFIER_BACKEND=claude, needs
// ANTHROPIC_API_KEY. Talks to the Messages API directly over HTTP rather
// than pulling in an SDK — one endpoint, one call shape, not worth the
// dependency.
type ClaudeClassifier struct {
	APIKey string
	Model  string
	Client *http.Client
}

func NewClaudeClassifier(apiKey, model string) *ClaudeClassifier {
	return &ClaudeClassifier{APIKey: apiKey, Model: model, Client: http.DefaultClient}
}

const classifierSystemPrompt = `You review transcribed song lyrics for a short-form devotional video platform (bhajans, mantras, stutis, chalisas, aartis, kirtan, sant vani, meditation/naad). Judge ONLY the lyrical subject matter of the transcript — never the audio quality, instrumentation, production style, or how traditional vs. modern the arrangement sounds. A heavily produced, synth-and-beat bhajan is still devotional; a plainly sung, acoustic romantic song is still not.

Classify into exactly one of:
- "devotional": invocation, deity/guru praise, scripture, prayer, spiritual longing, chanting a name or mantra.
- "secular": romantic, party, filmi storytelling, political, or otherwise not devotional in subject — this includes a devotional-sounding melody or deity's name used inside what is clearly a film song / romantic narrative, since the platform's own rule is about lyrical subject, not surface resemblance.
- "uncertain": genuinely mixed or ambiguous (e.g. a devotional theme woven into secular film storytelling in a way that isn't clearly one or the other), or the transcript gives too little real signal to judge confidently (near-empty, garbled, or just a few repeated syllables). Use this rather than guessing either way.

The transcript may be in Hindi, Sanskrit, or another Indian language, in its native script — read it as-is, do not ask for translation or transliteration.

Respond with ONLY a single JSON object, no other text: {"label": "devotional"|"secular"|"uncertain", "reason": "<one sentence, specific to what's in this transcript>"}`

type claudeMessagesRequest struct {
	Model     string          `json:"model"`
	MaxTokens int             `json:"max_tokens"`
	System    string          `json:"system"`
	Messages  []claudeMessage `json:"messages"`
}

type claudeMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type claudeMessagesResponse struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Error *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

func (c *ClaudeClassifier) Classify(ctx context.Context, transcript string) (*ClassifierVerdict, error) {
	trimmed := strings.TrimSpace(transcript)
	if trimmed == "" {
		return &ClassifierVerdict{
			Label:  LabelUncertain,
			Reason: "no transcript text to judge (likely instrumental or inaudible)",
		}, nil
	}

	reqBody := claudeMessagesRequest{
		Model:     c.Model,
		MaxTokens: 300,
		System:    classifierSystemPrompt,
		Messages: []claudeMessage{
			{Role: "user", Content: "Transcript:\n\n" + trimmed},
		},
	}
	payload, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.anthropic.com/v1/messages", bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.APIKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call anthropic api: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read anthropic response: %w", err)
	}

	var parsed claudeMessagesResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("parse anthropic response: %w: %s", err, truncate(string(respBody), 500))
	}
	if resp.StatusCode != http.StatusOK {
		msg := string(respBody)
		if parsed.Error != nil {
			msg = parsed.Error.Message
		}
		return nil, fmt.Errorf("anthropic api returned %d: %s", resp.StatusCode, msg)
	}
	if len(parsed.Content) == 0 {
		return nil, fmt.Errorf("anthropic response had no content")
	}

	return parseVerdictJSON(parsed.Content[0].Text)
}

// verdictJSON mirrors the {"label": ..., "reason": ...} shape the system
// prompt asks Claude to reply with.
type verdictJSON struct {
	Label  string `json:"label"`
	Reason string `json:"reason"`
}

func parseVerdictJSON(text string) (*ClassifierVerdict, error) {
	// The model is instructed to reply with only the JSON object, but
	// strip incidental surrounding whitespace/markdown fencing
	// defensively rather than fail a whole pipeline run over formatting.
	text = strings.TrimSpace(text)
	text = strings.TrimPrefix(text, "```json")
	text = strings.TrimPrefix(text, "```")
	text = strings.TrimSuffix(text, "```")
	text = strings.TrimSpace(text)

	var v verdictJSON
	if err := json.Unmarshal([]byte(text), &v); err != nil {
		return nil, fmt.Errorf("classifier did not return valid JSON: %w: %q", err, truncate(text, 500))
	}

	label := ClassifierLabel(v.Label)
	switch label {
	case LabelDevotional, LabelSecular, LabelUncertain:
	default:
		return nil, fmt.Errorf("classifier returned unrecognized label %q", v.Label)
	}
	return &ClassifierVerdict{Label: label, Reason: v.Reason}, nil
}

var _ IntentClassifier = (*ClaudeClassifier)(nil)
