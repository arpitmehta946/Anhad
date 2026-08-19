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

// japaStreakHandler reports the authenticated user's current/longest streak
// (docs/PRD.md §7.4) plus their all-time lifetime total
// (docs/ONBOARDING.md §1.3) for display on the japa screen. Bundled into
// one response rather than a separate endpoint since the mobile app already
// fetches this at the moments that matter (screen open, any successful
// sync) and both are cheap single-row reads.
func japaStreakHandler(logger *slog.Logger, japaSvc *japa.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}

		streak, err := japaSvc.GetStreak(r.Context(), claims.Subject)
		if err != nil {
			logger.Error("get japa streak failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load streak")
			return
		}
		lifetimeTotal, err := japaSvc.LifetimeTotal(r.Context(), claims.Subject)
		if err != nil {
			logger.Error("get japa lifetime total failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load lifetime total")
			return
		}

		resp := map[string]any{
			"current_streak": streak.CurrentStreak,
			"longest_streak": streak.LongestStreak,
			"lifetime_total": lifetimeTotal,
		}
		if streak.LastChantedDate != nil {
			resp["last_chanted_date"] = streak.LastChantedDate.Format("2006-01-02")
		}
		writeJSON(w, http.StatusOK, resp)
	}
}

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
			// 422: the request is well-formed, but this exact batch's own
			// recorded timing fails the anti-cheat checks (PRD.md §7.4) —
			// retrying identical data will fail identically forever, so the
			// client (japa_api_client.dart) treats this as a permanent
			// rejection and discards the batch rather than retrying it.
			// Logged at Warn since a spike in these for a legitimate user is
			// exactly what you'd want to notice.
			logger.Warn("japa anti-cheat rejection", "user_id", claims.Subject, "taps", len(req.Taps), "error", err)
			writeError(w, http.StatusUnprocessableEntity, err.Error())
		case errors.Is(err, japa.ErrBurstLimitExceeded):
			// 429, not 422: nothing about this batch's own content is
			// suspicious, it just landed close behind other recent activity
			// from the same user (docs/PRD.md §7.4's rate limit is meant to
			// catch bots, not punish legitimate batches that happen to sync
			// close together — e.g. an offline backlog catching up). Unlike
			// the 422s above, the client must NOT treat this as permanent:
			// it only throws JapaTapsRejected for 400/422, so a 429 here
			// falls through to the retry path and the batch stays queued
			// locally instead of being deleted.
			logger.Warn("japa cross-batch rate limit", "user_id", claims.Subject, "taps", len(req.Taps), "error", err)
			writeError(w, http.StatusTooManyRequests, err.Error())
		default:
			logger.Error("japa tap submission failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to record taps")
		}
	}
}
