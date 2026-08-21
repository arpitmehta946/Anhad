package moderation

import "context"

// ClassifierLabel is the classifier's verdict on a transcript's lyrical
// subject (docs/PRD.md §8.1's "is the lyrical subject divine reverence /
// scripture / invocation, vs. romantic / party / filmi storytelling?").
type ClassifierLabel string

const (
	LabelDevotional ClassifierLabel = "devotional"
	LabelSecular    ClassifierLabel = "secular"
	// LabelUncertain covers both "genuinely ambiguous" (a semi-devotional
	// ghazal) and "not enough signal to judge" (an empty or near-empty
	// transcript) — the pipeline treats both the same way: hold for a
	// human, never guess.
	LabelUncertain ClassifierLabel = "uncertain"
)

type ClassifierVerdict struct {
	Label ClassifierLabel
	// Reason is a short, human-readable justification — shown to the
	// moderator reviewing a held reel, and to the creator once the
	// notification/appeal surface (docs/GAPS.md, still unbuilt) exists.
	Reason string
}

// IntentClassifier judges a transcript's lyrical subject. Two
// implementations: KeywordClassifier (dev plumbing only — see its own doc
// for why this can never be the real thing) and ClaudeClassifier
// (CLASSIFIER_BACKEND=claude, needs ANTHROPIC_API_KEY — the actual
// judgment call docs/PRD.md §8.1 says a keyword list can't make).
type IntentClassifier interface {
	Classify(ctx context.Context, transcript string) (*ClassifierVerdict, error)
}
