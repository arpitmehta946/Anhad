package server

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/anhad/api/internal/auth"
	"github.com/anhad/api/internal/japa"
)

// submitJapaTapsHandler accepts a client-batched sequence of chant tap
// timestamps for the authenticated user (docs/TECH_STACK.md §5: the client
// batches and flushes periodically, e.g. every 108 taps or after 30s idle
// — this handler is that flush, not a per-tap call).
func submitJapaTapsHandler(logger *slog.Logger, japaSvc *japa.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}

		var req struct {
			Taps []time.Time `json:"taps"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}

		session, err := japaSvc.SubmitTaps(r.Context(), claims.Subject, req.Taps)
		switch {
		case err == nil:
			writeJSON(w, http.StatusCreated, map[string]any{
				"session_id": session.ID,
				"tap_count":  session.TapCount,
				"started_at": session.StartedAt,
				"ended_at":   session.EndedAt,
			})
		case errors.Is(err, japa.ErrEmptyBatch), errors.Is(err, japa.ErrTapsNotOrdered):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, japa.ErrUniformTiming), errors.Is(err, japa.ErrRateExceeded):
			// 422: the request is well-formed, but the anti-cheat checks
			// reject the batch itself (PRD.md §7.4).
			writeError(w, http.StatusUnprocessableEntity, err.Error())
		default:
			logger.Error("japa tap submission failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to record taps")
		}
	}
}
