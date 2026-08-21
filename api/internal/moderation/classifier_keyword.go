package moderation

import (
	"context"
	"strings"
)

// KeywordClassifier is dev plumbing only — it exists so the pipeline can
// be built, wired, and end-to-end tested (uploads still flow through all
// three layers) before an ANTHROPIC_API_KEY exists, the same role
// LocalVideoStorage plays before a Cloudflare account exists. It is not a
// substitute for ClaudeClassifier: docs/PRD.md §8.1 says outright that "a
// keyword blocklist alone will not work," and this eval package's own
// results prove it — see cmd/moderationeval. Never select
// CLASSIFIER_BACKEND=keyword outside local development.
type KeywordClassifier struct{}

func NewKeywordClassifier() *KeywordClassifier { return &KeywordClassifier{} }

// devotionalMarkers/secularMarkers are a small, deliberately unmaintained
// set of high-frequency terms — deity names, invocation words, common
// romantic/filmi vocabulary. This is intentionally not tuned for
// accuracy; tuning a keyword list closer to "working" would just
// reproduce the failure mode PRD.md §8.1 already warned about.
var devotionalMarkers = []string{
	"राम", "कृष्ण", "शिव", "हरि", "गोविन्द", "गोविंद", "जय", "ॐ", "मंत्र",
	"भजन", "आरती", "गुरु", "देव", "माता", "प्रभु", "भगवान", "आदेश",
	"ram", "krishna", "shiv", "hari", "govind", "jai", "om", "mantra",
	"bhajan", "aarti", "guru", "dev", "mata", "prabhu", "bhagwan",
}

var secularMarkers = []string{
	"प्यार", "इश्क", "दिल", "यार", "पार्टी",
	"pyaar", "pyar", "ishq", "dil", "yaar", "party", "love", "baby",
}

func (c *KeywordClassifier) Classify(ctx context.Context, transcript string) (*ClassifierVerdict, error) {
	trimmed := strings.TrimSpace(transcript)
	if trimmed == "" {
		return &ClassifierVerdict{
			Label:  LabelUncertain,
			Reason: "no transcript text to judge (likely instrumental or inaudible)",
		}, nil
	}

	lower := strings.ToLower(trimmed)
	devotionalHits, secularHits := 0, 0
	for _, m := range devotionalMarkers {
		if strings.Contains(lower, strings.ToLower(m)) {
			devotionalHits++
		}
	}
	for _, m := range secularMarkers {
		if strings.Contains(lower, strings.ToLower(m)) {
			secularHits++
		}
	}

	switch {
	case devotionalHits > 0 && secularHits == 0:
		return &ClassifierVerdict{
			Label:  LabelDevotional,
			Reason: "keyword stub: matched devotional-vocabulary terms, no secular terms (dev-only heuristic, not a real judgment)",
		}, nil
	case secularHits > 0 && devotionalHits == 0:
		return &ClassifierVerdict{
			Label:  LabelSecular,
			Reason: "keyword stub: matched secular/romantic-vocabulary terms, no devotional terms (dev-only heuristic, not a real judgment)",
		}, nil
	default:
		return &ClassifierVerdict{
			Label:  LabelUncertain,
			Reason: "keyword stub: no clear signal either way (dev-only heuristic, not a real judgment)",
		}, nil
	}
}

var _ IntentClassifier = (*KeywordClassifier)(nil)
