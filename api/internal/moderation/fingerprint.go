package moderation

import "context"

type FingerprintResult struct {
	Matched bool
	// Track, if Matched, is whatever the fingerprint service identified —
	// shown to the moderator reviewing a held reel as the concrete reason
	// it needs a human decision, not just "the classifier wasn't sure."
	Track string
}

// FingerprintChecker matches an upload's audio against a commercial-music
// database (docs/PRD.md §8.1's third layer). NoMatchFingerprintChecker
// (this package's default, FINGERPRINT_BACKEND=none) always reports no
// match — there is no free, reliable commercial-catalog fingerprint DB to
// stub against honestly, so unlike the other two layers this one has no
// dev-plumbing stand-in that proves anything. A real ACRCloud
// implementation (FINGERPRINT_BACKEND=acrcloud) needs an account and
// isn't built yet — see config.Load's validation.
type FingerprintChecker interface {
	Check(ctx context.Context, wavPath string) (*FingerprintResult, error)
}
