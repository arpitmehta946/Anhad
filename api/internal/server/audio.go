package server

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/anhad/api/internal/audio"
)

// listAudioLibraryHandler is reachable without a bearer token, same as
// listFeedHandler — the sound library is part of the same free-to-browse
// surface (docs/PRD.md: viewers browse for free), and nothing in the
// response shape depends on viewer identity the way a reel's viewer_*
// fields do.
func listAudioLibraryHandler(logger *slog.Logger, audioSvc *audio.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var category *string
		if c := r.URL.Query().Get("category"); c != "" {
			category = &c
		}

		var before *time.Time
		if c := r.URL.Query().Get("cursor"); c != "" {
			t, err := time.Parse(time.RFC3339, c)
			if err != nil {
				writeError(w, http.StatusBadRequest, "cursor must be an RFC3339 timestamp")
				return
			}
			before = &t
		}

		limit := 20
		tracks, err := audioSvc.ListLibrary(r.Context(), category, before, limit)
		if err != nil {
			logger.Error("list audio library failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load audio library")
			return
		}

		items := make([]map[string]any, len(tracks))
		for i, t := range tracks {
			items[i] = trackJSON(t)
		}
		resp := map[string]any{"tracks": items}
		if len(tracks) == limit {
			resp["next_cursor"] = tracks[len(tracks)-1].CreatedAt.Format(time.RFC3339Nano)
		}
		writeJSON(w, http.StatusOK, resp)
	}
}

// recordAudioPlayHandler increments a track's play_count — the raw signal
// the future royalty batch job (docs/PRD.md §10.4) will divide the monthly
// pool by. No auth required, same as playing the reel feed itself.
func recordAudioPlayHandler(logger *slog.Logger, audioSvc *audio.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		trackID := r.PathValue("id")
		if trackID == "" {
			writeError(w, http.StatusBadRequest, "track id required")
			return
		}

		err := audioSvc.RecordPlay(r.Context(), trackID)
		switch {
		case err == nil:
			w.WriteHeader(http.StatusNoContent)
		case errors.Is(err, audio.ErrTrackNotFound):
			writeError(w, http.StatusNotFound, err.Error())
		default:
			logger.Error("record audio play failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to record play")
		}
	}
}

func trackJSON(t *audio.Track) map[string]any {
	m := map[string]any{
		"id":          t.ID,
		"creator_id":  t.CreatorID,
		"audio_url":   t.AudioURL,
		"category":    t.Category,
		"reuse_count": t.ReuseCount,
		"play_count":  t.PlayCount,
		"created_at":  t.CreatedAt,
	}
	if t.SourceReelID != nil {
		m["source_reel_id"] = *t.SourceReelID
	}
	if t.CreatorDisplayName != nil {
		m["creator_display_name"] = *t.CreatorDisplayName
	}
	if t.Title != nil {
		m["title"] = *t.Title
	}
	return m
}
