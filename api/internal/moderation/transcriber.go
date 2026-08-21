package moderation

import "context"

// Transcript is what a Transcriber hands back. Empty Text (not an error)
// is a real, expected outcome — an instrumental with no lyrics
// (docs/GAPS.md's flagged instrumental gap) has nothing to transcribe,
// and the pipeline treats that as its own signal rather than a failure.
type Transcript struct {
	Text string
	// Language is whatever the transcriber detected (e.g. "hi", "sa",
	// "en") — carried through for the classifier prompt and for a human
	// moderator's context, not itself part of the devotional/secular
	// decision.
	Language string
}

// Transcriber turns an extracted audio track into (transliterated, per
// docs/PRD.md §8.1) text. Two implementations: WhisperCppTranscriber (this
// package's default — local, free, no account, selected by
// TRANSCRIBER_BACKEND=local) and OpenAIWhisperTranscriber
// (TRANSCRIBER_BACKEND=openai, needs OPENAI_API_KEY). Swapping is a config
// change, not a rewrite — the pipeline (pipeline.go) only ever talks to
// this interface, the same way internal/reels only ever talks to
// VideoStorage regardless of which backend is live.
type Transcriber interface {
	Transcribe(ctx context.Context, wavPath string) (*Transcript, error)
}
