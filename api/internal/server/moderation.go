package server

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/anhad/api/internal/auth"
	"github.com/anhad/api/internal/moderation"
)

// submitReportHandler files a report against a reel — any authenticated
// user (viewers included, not just creators/moderators: docs/PRD.md §7.8's
// "in-app reporting" is a viewer-facing safety feature, not a trust-tier
// one), gated only behind requireAuth.
func submitReportHandler(logger *slog.Logger, modSvc *moderation.Service) http.HandlerFunc {
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
			Reason string  `json:"reason"`
			Detail *string `json:"detail"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if req.Reason == "" {
			writeError(w, http.StatusBadRequest, "reason is required")
			return
		}

		report, err := modSvc.SubmitReport(r.Context(), claims.Subject, reelID, req.Reason, req.Detail)
		switch {
		case err == nil:
			writeJSON(w, http.StatusCreated, reportJSON(report))
		case errors.Is(err, moderation.ErrInvalidReason):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, moderation.ErrReelNotFound):
			writeError(w, http.StatusNotFound, err.Error())
		case errors.Is(err, moderation.ErrAlreadyReported):
			writeError(w, http.StatusConflict, err.Error())
		case errors.Is(err, moderation.ErrRateLimited):
			writeError(w, http.StatusTooManyRequests, err.Error())
		default:
			logger.Error("submit report failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to submit report")
		}
	}
}

// listModerationQueueHandler returns open reports for review — gated
// behind requireModerator, not requireRole("admin"): docs/GAPS.md's roles
// schema treats is_moderator as a flag layered on top of any role, so a
// creator or viewer who's also a trusted moderator (the normal case per
// docs/PRD.md §8.4, not an edge case) can reach this without also being
// an admin.
func listModerationQueueHandler(logger *slog.Logger, modSvc *moderation.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		items, err := modSvc.ListQueue(r.Context(), 50)
		if err != nil {
			logger.Error("list moderation queue failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load queue")
			return
		}

		out := make([]map[string]any, len(items))
		for i, item := range items {
			reel := map[string]any{
				"id":         item.ReelID,
				"video_url":  item.ReelVideoURL,
				"category":   item.ReelCategory,
				"creator_id": item.ReelCreatorID,
			}
			if item.ReelCaption != nil {
				reel["caption"] = *item.ReelCaption
			}
			m := reportJSON(&item.Report)
			m["reel"] = reel
			out[i] = m
		}
		writeJSON(w, http.StatusOK, map[string]any{"reports": out})
	}
}

// dismissReportHandler and removeReelHandler are the two actions a
// moderator can take on an open report — reviewed-no-action, or
// reviewed-and-removed. Both always write an audit log entry
// (internal/moderation.actOnReport), regardless of which one is chosen.

func dismissReportHandler(logger *slog.Logger, modSvc *moderation.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		handleModerationAction(w, r, logger, "dismiss report", modSvc.DismissReport)
	}
}

func removeReelHandler(logger *slog.Logger, modSvc *moderation.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		handleModerationAction(w, r, logger, "remove reel", modSvc.RemoveReel)
	}
}

// handleModerationAction is the shared HTTP glue behind both moderator
// actions: read the moderator's identity off the token, the report id off
// the path, an optional reason off the body, run whichever
// internal/moderation.Service method the caller passed, and map its
// sentinel errors to the right status codes.
func handleModerationAction(
	w http.ResponseWriter,
	r *http.Request,
	logger *slog.Logger,
	actionName string,
	action func(ctx context.Context, moderatorID, reportID string, reason *string) error,
) {
	claims, ok := auth.ClaimsFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	reportID := r.PathValue("id")
	if reportID == "" {
		writeError(w, http.StatusBadRequest, "report id required")
		return
	}

	var req struct {
		Reason *string `json:"reason"`
	}
	// A body is optional here — "remove, no reason given" is still a valid
	// (if less useful) moderator action, so a missing/empty body shouldn't
	// 400 the way a malformed one should.
	if r.ContentLength != 0 {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
	}

	err := action(r.Context(), claims.Subject, reportID, req.Reason)
	switch {
	case err == nil:
		w.WriteHeader(http.StatusNoContent)
	case errors.Is(err, moderation.ErrReportNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, moderation.ErrReportNotOpen):
		writeError(w, http.StatusConflict, err.Error())
	default:
		logger.Error(actionName+" failed", "error", err)
		writeError(w, http.StatusInternalServerError, "failed to "+actionName)
	}
}

// listAuditLogHandler exposes the moderation_audit_log trail — same
// moderator gate as the queue itself, since who-acted-on-what is exactly
// the kind of record a non-moderator shouldn't be able to browse either.
func listAuditLogHandler(logger *slog.Logger, modSvc *moderation.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		entries, err := modSvc.ListAuditLog(r.Context(), 100)
		if err != nil {
			logger.Error("list audit log failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load audit log")
			return
		}

		out := make([]map[string]any, len(entries))
		for i, e := range entries {
			m := map[string]any{
				"id":           e.ID,
				"moderator_id": e.ModeratorID,
				"reel_id":      e.ReelID,
				"action":       e.Action,
				"created_at":   e.CreatedAt,
			}
			if e.ReportID != nil {
				m["report_id"] = *e.ReportID
			}
			if e.Reason != nil {
				m["reason"] = *e.Reason
			}
			out[i] = m
		}
		writeJSON(w, http.StatusOK, map[string]any{"entries": out})
	}
}

func reportJSON(report *moderation.Report) map[string]any {
	m := map[string]any{
		"id":          report.ID,
		"reporter_id": report.ReporterID,
		"reel_id":     report.ReelID,
		"reason":      report.Reason,
		"status":      report.Status,
		"created_at":  report.CreatedAt,
	}
	if report.Detail != nil {
		m["detail"] = *report.Detail
	}
	return m
}

// requireModerator gates a handler behind is_moderator or role=admin — an
// admin can always moderate without also needing the flag set explicitly,
// matching how BOOTSTRAP_ADMIN_PHONE already treats admin as the ultimate
// fallback authority elsewhere in this codebase.
func requireModerator(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		if !claims.IsModerator && claims.Role != "admin" {
			writeError(w, http.StatusForbidden, "moderator access required")
			return
		}
		next.ServeHTTP(w, r)
	})
}
