package server

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/anhad/api/internal/auth"
	"github.com/anhad/api/internal/social"
)

// pranamHandler and smaranHandler are both plain toggles: call once to
// pranam/smaran a reel, call again to undo it. Deliberately POST rather
// than a DELETE/PUT pair — the caller doesn't need to know its own prior
// state to use the endpoint correctly, which matches how the mobile button
// itself works (tap toggles, it never has to ask "am I already active?"
// before deciding which verb to send).
func pranamHandler(logger *slog.Logger, socialSvc *social.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		handleReelToggle(w, r, logger, "toggle pranam", socialSvc.TogglePranam)
	}
}

func smaranHandler(logger *slog.Logger, socialSvc *social.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		handleReelToggle(w, r, logger, "toggle smaran", socialSvc.ToggleSmaran)
	}
}

func handleReelToggle(
	w http.ResponseWriter,
	r *http.Request,
	logger *slog.Logger,
	actionName string,
	toggle func(ctx context.Context, userID, reelID string) (bool, int64, error),
) {
	claims, ok := auth.ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	reelID := r.PathValue("id")
	if reelID == "" {
		writeError(w, http.StatusBadRequest, "reel id required")
		return
	}

	active, count, err := toggle(r.Context(), claims.Subject, reelID)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, map[string]any{"active": active, "count": count})
	case errors.Is(err, social.ErrReelNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	default:
		logger.Error(actionName+" failed", "error", err)
		writeError(w, http.StatusInternalServerError, "failed to "+actionName)
	}
}

// sevakHandler toggles the caller following the creator named in the path —
// docs/PRD.md §6: "joining a creator's circle."
func sevakHandler(logger *slog.Logger, socialSvc *social.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		creatorID := r.PathValue("id")
		if creatorID == "" {
			writeError(w, http.StatusBadRequest, "creator id required")
			return
		}

		active, err := socialSvc.ToggleSevak(r.Context(), claims.Subject, creatorID)
		switch {
		case err == nil:
			writeJSON(w, http.StatusOK, map[string]any{"active": active})
		case errors.Is(err, social.ErrCannotFollowSelf):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, social.ErrCreatorNotFound):
			writeError(w, http.StatusNotFound, err.Error())
		default:
			logger.Error("toggle sevak failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to toggle sevak")
		}
	}
}

// prasadHandler records a share — not a toggle (see
// internal/social.Service.RecordPrasad's own doc for why), so this just
// returns the new count, never an active flag.
func prasadHandler(logger *slog.Logger, socialSvc *social.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, ok := auth.ClaimsFromContext(r.Context()); !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		reelID := r.PathValue("id")
		if reelID == "" {
			writeError(w, http.StatusBadRequest, "reel id required")
			return
		}

		count, err := socialSvc.RecordPrasad(r.Context(), reelID)
		switch {
		case err == nil:
			writeJSON(w, http.StatusOK, map[string]any{"count": count})
		case errors.Is(err, social.ErrReelNotFound):
			writeError(w, http.StatusNotFound, err.Error())
		default:
			logger.Error("record prasad failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to record prasad")
		}
	}
}

// postSatsangHandler adds a comment/reflection to a reel.
func postSatsangHandler(logger *slog.Logger, socialSvc *social.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		reelID := r.PathValue("id")
		if reelID == "" {
			writeError(w, http.StatusBadRequest, "reel id required")
			return
		}

		var req struct {
			Body string `json:"body"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}

		comment, err := socialSvc.PostSatsang(r.Context(), claims.Subject, reelID, req.Body)
		switch {
		case err == nil:
			writeJSON(w, http.StatusCreated, satsangCommentJSON(comment))
		case errors.Is(err, social.ErrCommentEmpty):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, social.ErrCommentTooLong):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, social.ErrReelNotFound):
			writeError(w, http.StatusNotFound, err.Error())
		default:
			logger.Error("post satsang failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to post comment")
		}
	}
}

// listSatsangHandler reads a reel's comments — unauthenticated, matching
// listFeedHandler's own "reading is free" stance (docs/PRD.md).
func listSatsangHandler(logger *slog.Logger, socialSvc *social.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		reelID := r.PathValue("id")
		if reelID == "" {
			writeError(w, http.StatusBadRequest, "reel id required")
			return
		}

		var after *time.Time
		if c := r.URL.Query().Get("cursor"); c != "" {
			t, err := time.Parse(time.RFC3339, c)
			if err != nil {
				writeError(w, http.StatusBadRequest, "cursor must be an RFC3339 timestamp")
				return
			}
			after = &t
		}

		limit := 50
		comments, err := socialSvc.ListSatsang(r.Context(), reelID, after, limit)
		if err != nil {
			logger.Error("list satsang failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load comments")
			return
		}

		items := make([]map[string]any, len(comments))
		for i, c := range comments {
			items[i] = satsangCommentJSON(c)
		}
		resp := map[string]any{"comments": items}
		if len(comments) == limit {
			resp["next_cursor"] = comments[len(comments)-1].CreatedAt.Format(time.RFC3339Nano)
		}
		writeJSON(w, http.StatusOK, resp)
	}
}

func satsangCommentJSON(c *social.Comment) map[string]any {
	m := map[string]any{
		"id":         c.ID,
		"reel_id":    c.ReelID,
		"user_id":    c.UserID,
		"body":       c.Body,
		"created_at": c.CreatedAt,
	}
	if c.UserDisplayName != nil {
		m["user_display_name"] = *c.UserDisplayName
	}
	return m
}
