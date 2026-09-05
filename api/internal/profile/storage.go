package profile

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// AvatarStorage is where a profile's avatar image actually lives. Unlike
// internal/reels.VideoStorage, there's no pre-signed-upload-target dance
// here: an avatar is small enough that receiving it directly at this
// API's own origin is fine even in production (TECH_STACK.md §3's "raw
// video never hits this API's own origin" rule is specifically about
// large video, not a few-hundred-KB image), so Save takes the bytes
// directly in one step.
type AvatarStorage interface {
	// Save stores r's bytes under a new, unguessable id and returns the
	// URL to persist as the user's avatar_url.
	Save(ctx context.Context, r io.Reader) (url string, err error)
}

// LocalAvatarStorage is the local-dev stand-in — same honest-stub shape as
// internal/reels.LocalVideoStorage: a real implementation, not a mock, it
// just serves the file back from this process's own disk rather than a
// real object store.
type LocalAvatarStorage struct {
	dir           string
	publicBaseURL string
}

func NewLocalAvatarStorage(dir, publicBaseURL string) (*LocalAvatarStorage, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create local avatar dir: %w", err)
	}
	return &LocalAvatarStorage{dir: dir, publicBaseURL: publicBaseURL}, nil
}

func (s *LocalAvatarStorage) Save(ctx context.Context, r io.Reader) (string, error) {
	id, err := newAvatarID()
	if err != nil {
		return "", fmt.Errorf("generate avatar id: %w", err)
	}

	f, err := os.Create(s.filePath(id))
	if err != nil {
		return "", fmt.Errorf("create local avatar file: %w", err)
	}
	defer f.Close()
	if _, err := io.Copy(f, r); err != nil {
		return "", fmt.Errorf("write local avatar file: %w", err)
	}

	return fmt.Sprintf("%s/v1/profile/avatars/%s/file", s.publicBaseURL, id), nil
}

// Open returns a saved avatar's bytes for the local-only GET
// .../avatars/{id}/file route.
func (s *LocalAvatarStorage) Open(id string) (*os.File, error) {
	return os.Open(s.filePath(id))
}

func (s *LocalAvatarStorage) filePath(id string) string {
	return filepath.Join(s.dir, id+".img")
}

func newAvatarID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
