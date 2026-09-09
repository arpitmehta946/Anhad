package reels

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// ErrNotAVideo means Save received bytes ffmpeg can't decode at all — the
// upload is rejected outright rather than being written to disk under a
// real reel. Found the hard way: a handful of pre-moderation-pipeline test
// reels (created before this package's own history added real moderation)
// had rows pointing at files that were never video at all, one literally
// containing the text "dummy video bytes". The moderation worker's own
// ExtractAudio (internal/moderation/audio.go) would already fail on such a
// file, but silently — RunAndSave logs the error and leaves the reel at
// 'pending' forever, invisible in both the public feed and the moderator
// queue, retried by Asynq until it's exhausted and quietly archived. Much
// cheaper to refuse the upload at the one point a clear, immediate error
// can still reach the uploader, than to let a phantom reel exist at all.
var ErrNotAVideo = errors.New("uploaded file is not a valid video")

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
	// ffmpegPath is used only to validate an uploaded file decodes as a
	// real video before Save accepts it (see ErrNotAVideo's own doc) — the
	// same binary internal/moderation.ExtractAudio uses, just invoked here
	// as a cheap parse-check rather than a real extraction.
	ffmpegPath string
}

func NewLocalVideoStorage(dir, publicBaseURL, ffmpegPath string) (*LocalVideoStorage, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create local upload dir: %w", err)
	}
	return &LocalVideoStorage{dir: dir, publicBaseURL: publicBaseURL, ffmpegPath: ffmpegPath}, nil
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
// also talks to a real VideoStorage backend. Written to a temp file in the
// same directory first (so the final rename is same-filesystem and atomic)
// and only promoted to videoID's real path once ffmpeg confirms it can
// actually decode the file — returns ErrNotAVideo otherwise, and the temp
// file is removed either way. Cloudflare Stream would reject non-video
// uploads on its own in production (TECH_STACK.md §3); this is this local
// stand-in's own version of that same guarantee, not extra behavior a real
// backend wouldn't already have.
func (s *LocalVideoStorage) Save(videoID string, r io.Reader) error {
	tmp, err := os.CreateTemp(s.dir, videoID+"-*.tmp")
	if err != nil {
		return fmt.Errorf("create temp video file: %w", err)
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath) // no-op once renamed below; cleans up on every error path
	if _, err := io.Copy(tmp, r); err != nil {
		tmp.Close()
		return fmt.Errorf("write local video file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close local video file: %w", err)
	}

	if !s.looksLikeVideo(tmpPath) {
		return ErrNotAVideo
	}

	if err := os.Rename(tmpPath, s.filePath(videoID)); err != nil {
		return fmt.Errorf("promote local video file: %w", err)
	}
	return nil
}

// looksLikeVideo decodes up to the first half-second of path and reports
// whether ffmpeg could make sense of it at all — cheap regardless of the
// real file's length (ffmpeg just stops at end-of-input if it's shorter
// than that), and deliberately not a full-file scan: this only needs to
// catch "not a video at all" (an empty file, a text placeholder, a stray
// image), the same class of input ExtractAudio would otherwise fail on
// silently and asynchronously much later.
func (s *LocalVideoStorage) looksLikeVideo(path string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, s.ffmpegPath,
		"-v", "error",
		"-i", path,
		"-t", "0.5",
		"-f", "null",
		"-",
	)
	return cmd.Run() == nil
}

// Open returns the uploaded file for the local-only GET
// .../uploads/{id}/file playback route.
func (s *LocalVideoStorage) Open(videoID string) (*os.File, error) {
	return os.Open(s.filePath(videoID))
}

func (s *LocalVideoStorage) filePath(videoID string) string {
	return filepath.Join(s.dir, videoID+".mp4")
}
