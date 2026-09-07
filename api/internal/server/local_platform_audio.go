package server

import (
	"errors"
	"log/slog"
	"mime"
	"net/http"
	"os"
	"path/filepath"

	"github.com/anhad/api/internal/audio"
)

// playLocalPlatformAudioHandler exists only because a local disk-backed
// stand-in, unlike R2, needs *something* on this process to actually serve
// a seeded track's bytes back — same reasoning as
// server/local_video.go's playLocalVideoHandler, for platform audio instead
// of reel video. Always registered (see server.go): unlike video storage,
// there's no non-local backend to switch to yet, matching
// profile.LocalAvatarStorage's own "nothing to switch to" stance.
func playLocalPlatformAudioHandler(logger *slog.Logger, storage *audio.LocalPlatformAudioStorage) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		filename := r.PathValue("filename")
		f, err := storage.Open(filename)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				writeError(w, http.StatusNotFound, "audio file not found")
				return
			}
			logger.Error("local platform audio open failed", "filename", filename, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to read audio")
			return
		}
		defer f.Close()

		info, err := f.Stat()
		if err != nil {
			logger.Error("local platform audio stat failed", "filename", filename, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to read audio")
			return
		}

		contentType := mime.TypeByExtension(filepath.Ext(filename))
		if contentType == "" {
			contentType = "audio/mpeg"
		}
		w.Header().Set("Content-Type", contentType)
		http.ServeContent(w, r, filename, info.ModTime(), f)
	}
}
