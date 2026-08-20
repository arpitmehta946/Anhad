package reels

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"time"
)

// UploadTarget is what a client needs to upload a video directly to
// storage — matching TECH_STACK.md §3's rule that raw video never hits
// this API's own origin in production: the server only ever hands out a
// short-lived target, it never receives the bytes itself.
type UploadTarget struct {
	VideoID string
	// UploadURL is where the client uploads the raw video bytes to —
	// Cloudflare's own direct-upload endpoint in production, this
	// process's own local-stub route in development (see
	// LocalVideoStorage).
	UploadURL string
	// UploadMethod is the HTTP method the client must use against
	// UploadURL. The client reads this rather than assuming one, since
	// Cloudflare Stream's direct-upload endpoint expects a POST
	// (multipart/TUS) while the local stub expects a plain PUT of the raw
	// bytes.
	UploadMethod string
	// ExpiresAt matches TECH_STACK.md §3's "5-minute validity" for a
	// pre-signed upload URL.
	ExpiresAt time.Time
}

// VideoStorage is where reel video actually lives. Two implementations:
// LocalVideoStorage (this file's sibling, a disk-backed stand-in used by
// default so the upload/feed flow can be built and tested with no
// Cloudflare account) and a future CloudflareVideoStorage implementing the
// same interface against the real Stream API (TECH_STACK.md §3) — not
// built yet, since there's nothing to verify it against without a real
// account and token. Swapping backends later means writing that one file
// and changing VIDEO_STORAGE_BACKEND; nothing else in this package, or the
// HTTP layer above it, needs to change.
type VideoStorage interface {
	// CreateUploadTarget reserves a new video ID and returns where the
	// client should upload its bytes to.
	CreateUploadTarget(ctx context.Context) (*UploadTarget, error)
	// PlaybackURL returns the URL to store on the reel and serve to
	// viewers once videoID's upload has actually completed. ready is
	// false (with an empty url and nil error) if the upload hasn't
	// finished yet — that's an expected, non-error outcome the caller
	// checks, not a fault.
	PlaybackURL(ctx context.Context, videoID string) (url string, ready bool, err error)
}

// newVideoID generates an unguessable identifier for a not-yet-uploaded
// video — hand-rolled with crypto/rand rather than pulling in a UUID
// dependency, matching the existing pattern in
// internal/auth/token.go's generateRandomToken.
func newVideoID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
