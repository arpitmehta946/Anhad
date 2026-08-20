package server

import (
	"errors"
	"log/slog"
	"net/http"
	"os"

	"github.com/anhad/api/internal/reels"
)

// uploadLocalVideoHandler and playLocalVideoHandler exist only for
// VIDEO_STORAGE_BACKEND=local — they're this process's own stand-in for
// what would otherwise be Cloudflare Stream's edge receiving and serving
// the bytes directly. Neither is registered at all when the real backend
// is configured (see New in server.go), since there'd be nothing for them
// to do — a client talking to Cloudflare never routes video bytes through
// this API in the first place.

func uploadLocalVideoHandler(logger *slog.Logger, storage *reels.LocalVideoStorage) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		videoID := r.PathValue("id")
		if videoID == "" {
			writeError(w, http.StatusBadRequest, "video id required")
			return
		}
		if err := storage.Save(videoID, r.Body); err != nil {
			logger.Error("local video upload failed", "video_id", videoID, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to store video")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func playLocalVideoHandler(logger *slog.Logger, storage *reels.LocalVideoStorage) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		videoID := r.PathValue("id")
		f, err := storage.Open(videoID)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				writeError(w, http.StatusNotFound, "video not found")
				return
			}
			logger.Error("local video open failed", "video_id", videoID, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to read video")
			return
		}
		defer f.Close()

		info, err := f.Stat()
		if err != nil {
			logger.Error("local video stat failed", "video_id", videoID, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to read video")
			return
		}

		w.Header().Set("Content-Type", "video/mp4")
		http.ServeContent(w, r, videoID+".mp4", info.ModTime(), f)
	}
}
