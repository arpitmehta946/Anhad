package reels

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// LocalVideoStorage is a disk-backed stand-in for Cloudflare Stream
// (TECH_STACK.md §3), used by default (VIDEO_STORAGE_BACKEND=local) so the
// upload/feed flow can be built and verified end to end with no Cloudflare
// account. It's a real implementation of VideoStorage, not a mock — the
// upload target it hands out really is a URL a client must PUT bytes to
// before the video exists, and PlaybackURL really does check.
//
// Two extra methods (Save, Open) beyond the VideoStorage interface exist
// only because a local stub, unlike Cloudflare, needs *something* on this
// process to actually receive and re-serve the bytes — see
// internal/server/reels.go's file-upload/playback routes, which are only
// registered when this backend is active.
type LocalVideoStorage struct {
	dir           string
	publicBaseURL string
}

func NewLocalVideoStorage(dir, publicBaseURL string) (*LocalVideoStorage, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create local upload dir: %w", err)
	}
	return &LocalVideoStorage{dir: dir, publicBaseURL: publicBaseURL}, nil
}

func (s *LocalVideoStorage) CreateUploadTarget(ctx context.Context) (*UploadTarget, error) {
	id, err := newVideoID()
	if err != nil {
		return nil, fmt.Errorf("generate video id: %w", err)
	}
	return &UploadTarget{
		VideoID:      id,
		UploadURL:    fmt.Sprintf("%s/v1/reels/uploads/%s/file", s.publicBaseURL, id),
		UploadMethod: "PUT",
		ExpiresAt:    time.Now().Add(5 * time.Minute),
	}, nil
}

func (s *LocalVideoStorage) PlaybackURL(ctx context.Context, videoID string) (string, bool, error) {
	if _, err := os.Stat(s.filePath(videoID)); err != nil {
		if os.IsNotExist(err) {
			return "", false, nil
		}
		return "", false, fmt.Errorf("stat uploaded file: %w", err)
	}
	return fmt.Sprintf("%s/v1/reels/uploads/%s/file", s.publicBaseURL, videoID), true, nil
}

// Save writes an uploaded video's bytes to disk under videoID — called by
// the local-only PUT .../uploads/{id}/file route, never by anything that
// also talks to a real VideoStorage backend.
func (s *LocalVideoStorage) Save(videoID string, r io.Reader) error {
	f, err := os.Create(s.filePath(videoID))
	if err != nil {
		return fmt.Errorf("create local video file: %w", err)
	}
	defer f.Close()
	if _, err := io.Copy(f, r); err != nil {
		return fmt.Errorf("write local video file: %w", err)
	}
	return nil
}

// Open returns the uploaded file for the local-only GET
// .../uploads/{id}/file playback route.
func (s *LocalVideoStorage) Open(videoID string) (*os.File, error) {
	return os.Open(s.filePath(videoID))
}

func (s *LocalVideoStorage) filePath(videoID string) string {
	return filepath.Join(s.dir, videoID+".mp4")
}
