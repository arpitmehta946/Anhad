package audio

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// LocalPlatformAudioStorage is where a seeded platform track's actual audio
// file lives — the same disk-backed-stand-in shape as
// internal/reels.LocalVideoStorage, for the same reason: these are
// server-origin static files (a tanpura drone recording, not something a
// client uploads), so a real backend would be R2 (docs/TECH_STACK.md §3),
// but there's no account to build and verify that against yet. Unlike
// LocalVideoStorage there's no client-facing upload target to hand out —
// cmd/seedaudio is the only caller, ingesting a file already sitting on
// this machine's disk.
type LocalPlatformAudioStorage struct {
	dir           string
	publicBaseURL string
}

func NewLocalPlatformAudioStorage(dir, publicBaseURL string) (*LocalPlatformAudioStorage, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("create local platform audio dir: %w", err)
	}
	return &LocalPlatformAudioStorage{dir: dir, publicBaseURL: publicBaseURL}, nil
}

// Ingest copies the audio file at srcPath into storage under a freshly
// generated id, preserving its extension (server/local_platform_audio.go's
// playback route needs it to set the right Content-Type, and re-encoding
// every seed file to one fixed format is more than this stub needs to do),
// and returns the URL to store as the resulting audio_library row's
// r2_url.
func (s *LocalPlatformAudioStorage) Ingest(srcPath string) (string, error) {
	id, err := newTrackFileID()
	if err != nil {
		return "", fmt.Errorf("generate track file id: %w", err)
	}
	filename := id + filepath.Ext(srcPath)

	src, err := os.Open(srcPath)
	if err != nil {
		return "", fmt.Errorf("open source audio file: %w", err)
	}
	defer src.Close()

	dst, err := os.Create(filepath.Join(s.dir, filename))
	if err != nil {
		return "", fmt.Errorf("create stored audio file: %w", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		return "", fmt.Errorf("copy audio file: %w", err)
	}

	return fmt.Sprintf("%s/v1/audio-tracks/platform/%s", s.publicBaseURL, filename), nil
}

// Open serves a previously-ingested file back for the GET
// .../audio-tracks/platform/{filename} route — filename is the same id+ext
// Ingest returned as the tail of its URL. filepath.Base guards against a
// request path smuggling a directory traversal in, since filename here
// comes straight from an HTTP path value.
func (s *LocalPlatformAudioStorage) Open(filename string) (*os.File, error) {
	return os.Open(filepath.Join(s.dir, filepath.Base(filename)))
}

func newTrackFileID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
