package moderation

import "context"

// NoMatchFingerprintChecker is the default FingerprintChecker
// (FINGERPRINT_BACKEND=none) — always reports no match. This means the
// fingerprint layer currently contributes nothing to any pipeline
// decision or eval accuracy number; it exists so the pipeline's shape
// (three layers, one of which may later force a hold regardless of what
// the classifier says) is already correct and only needs a real
// implementation dropped in, not a redesign, once there's an ACRCloud
// account to build one against.
type NoMatchFingerprintChecker struct{}

func NewNoMatchFingerprintChecker() *NoMatchFingerprintChecker {
	return &NoMatchFingerprintChecker{}
}

func (c *NoMatchFingerprintChecker) Check(ctx context.Context, wavPath string) (*FingerprintResult, error) {
	return &FingerprintResult{Matched: false}, nil
}

var _ FingerprintChecker = (*NoMatchFingerprintChecker)(nil)
