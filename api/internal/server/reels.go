package server

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/anhad/api/internal/auth"
	"github.com/anhad/api/internal/reels"
	"github.com/anhad/api/internal/social"
)

// createUploadTargetHandler hands a creator a fresh place to upload a
// video to (docs/TECH_STACK.md §3) — no reel exists yet, and none of this
// request's body matters (there isn't one); the caller's identity comes
// entirely from the bearer token already validated by requireAuth/
// requireRole.
func createUploadTargetHandler(logger *slog.Logger, reelsSvc *reels.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		target, err := reelsSvc.CreateUploadTarget(r.Context())
		if err != nil {
			logger.Error("create upload target failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to create upload target")
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{
			"video_id":      target.VideoID,
			"upload_url":    target.UploadURL,
			"upload_method": target.UploadMethod,
			"expires_at":    target.ExpiresAt,
		})
	}
}

// createReelHandler finalizes an already-uploaded video into a reel —
// category is mandatory (docs/PRD.md §4.1), and the row always lands
// PENDING regardless of anything the client sends (reels.Service.CreateReel
// doesn't accept a status from the caller at all). jugalbandi_enabled is
// optional — omitted/null means "use the default for my account"
// (reels.Service.CreateReel/insertReelTx's own doc explains how that
// default is resolved).
func createReelHandler(logger *slog.Logger, reelsSvc *reels.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}

		var req struct {
			VideoID           string  `json:"video_id"`
			Category          string  `json:"category"`
			Caption           *string `json:"caption"`
			JugalbandiEnabled *bool   `json:"jugalbandi_enabled"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if req.VideoID == "" || req.Category == "" {
			writeError(w, http.StatusBadRequest, "video_id and category are required")
			return
		}

		reel, err := reelsSvc.CreateReel(r.Context(), claims.Subject, req.VideoID, req.Category, req.Caption, req.JugalbandiEnabled)
		switch {
		case err == nil:
			// A brand new reel has no engagement yet and its own creator
			// can't pranam/smaran/sevak it (ErrCannotFollowSelf's whole
			// point) — false/false/false is the only correct viewer state.
			writeJSON(w, http.StatusCreated, reelJSON(reel, false, false, false))
		case errors.Is(err, reels.ErrInvalidCategory):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, reels.ErrUploadNotReady):
			writeError(w, http.StatusConflict, err.Error())
		default:
			logger.Error("create reel failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to create reel")
		}
	}
}

// createJugalbandiHandler finalizes an already-uploaded video into a duet
// result recorded alongside the reel named in the path (docs/PRD.md §7.2)
// — same shape as createReelHandler, minus the Jugalbandi-toggle field
// (which only makes sense on the reel granting/denying duets, not the one
// being recorded against it).
func createJugalbandiHandler(logger *slog.Logger, reelsSvc *reels.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		sourceReelID := r.PathValue("id")
		if sourceReelID == "" {
			writeError(w, http.StatusBadRequest, "reel id required")
			return
		}

		var req struct {
			VideoID  string  `json:"video_id"`
			Category string  `json:"category"`
			Caption  *string `json:"caption"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if req.VideoID == "" || req.Category == "" {
			writeError(w, http.StatusBadRequest, "video_id and category are required")
			return
		}

		reel, err := reelsSvc.CreateJugalbandi(r.Context(), claims.Subject, sourceReelID, req.VideoID, req.Category, req.Caption)
		switch {
		case err == nil:
			writeJSON(w, http.StatusCreated, reelJSON(reel, false, false, false))
		case errors.Is(err, reels.ErrInvalidCategory):
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, reels.ErrUploadNotReady):
			writeError(w, http.StatusConflict, err.Error())
		case errors.Is(err, reels.ErrSourceReelNotFound):
			writeError(w, http.StatusNotFound, err.Error())
		case errors.Is(err, reels.ErrSourceReelNotApproved):
			writeError(w, http.StatusConflict, err.Error())
		case errors.Is(err, reels.ErrJugalbandiDisabled):
			writeError(w, http.StatusForbidden, err.Error())
		default:
			logger.Error("create jugalbandi failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to create jugalbandi")
		}
	}
}

// listFeedHandler is deliberately reachable without a bearer token —
// docs/PRD.md's own pitch is that viewers browse for free, and the
// onboarding flow already defers signup past a person's first real
// activity, so the feed itself has no reason to be the thing that finally
// demands an account. It's wired through optionalAuth rather than left
// with no auth handling at all, though: a signed-in caller still gets their
// own Pranam/Smaran/Sevak state folded into each reel via reelJSON's
// viewer_* fields below; an anonymous one just doesn't.
func listFeedHandler(logger *slog.Logger, reelsSvc *reels.Service, socialSvc *social.Service) http.HandlerFunc {
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
		reelsList, err := reelsSvc.ListFeed(r.Context(), category, before, limit)
		if err != nil {
			logger.Error("list feed failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load feed")
			return
		}

		var pranamed, smaraned, following map[string]bool
		if claims, ok := auth.ClaimsFromContext(r.Context()); ok {
			reelIDs := make([]string, len(reelsList))
			creatorIDs := make([]string, len(reelsList))
			for i, reel := range reelsList {
				reelIDs[i] = reel.ID
				creatorIDs[i] = reel.CreatorID
			}
			pranamed, smaraned, following, err = socialSvc.ViewerState(r.Context(), claims.Subject, reelIDs, creatorIDs)
			if err != nil {
				// A viewer-state failure shouldn't turn "load the feed" into
				// a 500 — every reel just renders as not-yet-pranam'd/
				// smaran'd/followed for this response, which is wrong but
				// recoverable the moment the next page loads successfully.
				logger.Error("load viewer state failed", "error", err)
			}
		}

		items := make([]map[string]any, len(reelsList))
		for i, reel := range reelsList {
			items[i] = reelJSON(reel, pranamed[reel.ID], smaraned[reel.ID], following[reel.CreatorID])
		}
		resp := map[string]any{"reels": items}
		if len(reelsList) == limit {
			resp["next_cursor"] = reelsList[len(reelsList)-1].CreatedAt.Format(time.RFC3339Nano)
		}
		writeJSON(w, http.StatusOK, resp)
	}
}

// reelJSON always includes the four engagement counts and the creator's
// comments_mode — every caller of ListFeed selects them now
// (internal/reels.Service.ListFeed), so there's no partial-data case to
// branch on. The three viewer_* fields are only meaningful for a signed-in
// caller; listFeedHandler passes false for all three on an anonymous
// request; the client tells the two cases apart via whether it has a
// session at all, not via anything in this payload.
func reelJSON(reel *reels.Reel, viewerPranamed, viewerSmaraned, viewerFollowingCreator bool) map[string]any {
	m := map[string]any{
		"id":                       reel.ID,
		"creator_id":               reel.CreatorID,
		"video_url":                reel.VideoURL,
		"category":                 reel.Category,
		"status":                   reel.ModerationStatus,
		"comments_mode":            reel.CreatorCommentsMode,
		"pranam_count":             reel.PranamCount,
		"satsang_count":            reel.SatsangCount,
		"prasad_count":             reel.PrasadCount,
		"smaran_count":             reel.SmaranCount,
		"viewer_pranamed":          viewerPranamed,
		"viewer_smaraned":          viewerSmaraned,
		"viewer_following_creator": viewerFollowingCreator,
		"jugalbandi_enabled":       reel.JugalbandiEnabled,
		"jugalbandi_reuse_count":   reel.JugalbandiReuseCount,
		"created_at":               reel.CreatedAt,
	}
	if reel.Caption != nil {
		m["caption"] = *reel.Caption
	}
	if reel.CreatorDisplayName != nil {
		m["creator_display_name"] = *reel.CreatorDisplayName
	}
	// The jugalbandi_source_* fields are only ever present together — this
	// reel either is a duet result (source reel found, attribution
	// complete) or it isn't (jugalbandi_source_id was NULL, every field in
	// this block is nil) — never a partial set.
	if reel.JugalbandiSourceID != nil {
		m["jugalbandi_source_id"] = *reel.JugalbandiSourceID
		if reel.JugalbandiSourceVideoURL != nil {
			m["jugalbandi_source_video_url"] = *reel.JugalbandiSourceVideoURL
		}
		if reel.JugalbandiSourceCaption != nil {
			m["jugalbandi_source_caption"] = *reel.JugalbandiSourceCaption
		}
		if reel.JugalbandiSourceCreatorID != nil {
			m["jugalbandi_source_creator_id"] = *reel.JugalbandiSourceCreatorID
		}
		if reel.JugalbandiSourceCreatorDisplayName != nil {
			m["jugalbandi_source_creator_display_name"] = *reel.JugalbandiSourceCreatorDisplayName
		}
	}
	return m
}

// requireRole gates a handler behind an exact role match — used here for
// "only creators can upload" (this feature's own explicit instruction),
// composed after requireAuth so claims are already on the context.
// Deliberately an exact match, not "at least this privileged": there's no
// role hierarchy in this schema (docs/GAPS.md "Roles & permissions" —
// role/status/permission-flags are separate axes on purpose), so an admin
// who also needs to upload would need the creator role explicitly, the
// same as anyone else.
func requireRole(role string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := auth.ClaimsFromContext(r.Context())
			if !ok {
				writeError(w, http.StatusUnauthorized, "unauthorized")
				return
			}
			if claims.Role != role {
				writeError(w, http.StatusForbidden, role+" role required")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
