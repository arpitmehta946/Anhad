package server

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strings"

	"github.com/anhad/api/internal/auth"
	"github.com/anhad/api/internal/profile"
)

// maxAvatarBytes bounds an avatar upload — an avatar is a small profile
// image, not a video; there's no legitimate reason for one to be large,
// and no moderation/streaming pipeline exists for this upload path the
// way there is for reels.
const maxAvatarBytes = 5 << 20 // 5 MiB

// getProfileHandler is reachable without a bearer token, same as
// listFeedHandler — a creator profile is exactly the kind of thing a free
// viewer taps into from the feed, and there's no reason to demand an
// account just to look at one. A signed-in caller still gets
// viewer_is_following folded in.
func getProfileHandler(logger *slog.Logger, profileSvc *profile.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := r.PathValue("id")
		if userID == "" {
			writeError(w, http.StatusBadRequest, "user id required")
			return
		}

		var viewerID *string
		if claims, ok := auth.ClaimsFromContext(r.Context()); ok {
			viewerID = &claims.Subject
		}

		p, err := profileSvc.GetProfile(r.Context(), userID, viewerID)
		switch {
		case err == nil:
			writeJSON(w, http.StatusOK, profileJSON(p))
		case errors.Is(err, profile.ErrProfileNotFound):
			writeError(w, http.StatusNotFound, err.Error())
		default:
			logger.Error("get profile failed", "user_id", userID, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to load profile")
		}
	}
}

// updateProfileHandler edits the caller's own profile — always the full
// set of editable fields, since this is a full profile-edit form rather
// than a sparse patch (internal/profile.Service.ProfileEdits's own doc
// explains why that lets an empty value mean "cleared" unambiguously).
func updateProfileHandler(logger *slog.Logger, profileSvc *profile.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}

		var req struct {
			DisplayName string   `json:"display_name"`
			Bio         string   `json:"bio"`
			Tradition   string   `json:"tradition"`
			Lineage     string   `json:"lineage"`
			Languages   []string `json:"languages"`
			Instruments []string `json:"instruments"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}

		p, err := profileSvc.UpdateProfile(r.Context(), claims.Subject, profile.ProfileEdits{
			DisplayName: req.DisplayName,
			Bio:         req.Bio,
			Tradition:   req.Tradition,
			Lineage:     req.Lineage,
			Languages:   req.Languages,
			Instruments: req.Instruments,
		})
		switch {
		case err == nil:
			writeJSON(w, http.StatusOK, profileJSON(p))
		case errors.Is(err, profile.ErrBioTooLong),
			errors.Is(err, profile.ErrTraditionTooLong),
			errors.Is(err, profile.ErrLineageTooLong),
			errors.Is(err, profile.ErrTooManyLanguages),
			errors.Is(err, profile.ErrTooManyInstruments):
			writeError(w, http.StatusBadRequest, err.Error())
		default:
			logger.Error("update profile failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to update profile")
		}
	}
}

// uploadAvatarHandler replaces the caller's own avatar — the request body
// is the raw image bytes, not a JSON envelope or a pre-signed-upload-target
// dance (internal/profile.AvatarStorage's own doc explains why an avatar
// doesn't need that).
func uploadAvatarHandler(logger *slog.Logger, profileSvc *profile.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}

		contentType := r.Header.Get("Content-Type")
		if !strings.HasPrefix(contentType, "image/") {
			writeError(w, http.StatusBadRequest, "avatar must be an image")
			return
		}

		body := http.MaxBytesReader(w, r.Body, maxAvatarBytes)
		p, err := profileSvc.SaveAvatar(r.Context(), claims.Subject, body)
		if err != nil {
			var maxBytesErr *http.MaxBytesError
			if errors.As(err, &maxBytesErr) {
				writeError(w, http.StatusRequestEntityTooLarge, "avatar must be 5MB or smaller")
				return
			}
			logger.Error("upload avatar failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to upload avatar")
			return
		}
		writeJSON(w, http.StatusOK, profileJSON(p))
	}
}

// playLocalAvatarHandler exists only for the local avatar-storage stub,
// same "not registered at all against a real backend" shape as
// internal/server/local_video.go's playLocalVideoHandler — there's nothing
// for this to do once avatars are served straight from real object storage.
func playLocalAvatarHandler(logger *slog.Logger, storage *profile.LocalAvatarStorage) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		f, err := storage.Open(id)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				writeError(w, http.StatusNotFound, "avatar not found")
				return
			}
			logger.Error("local avatar open failed", "avatar_id", id, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to read avatar")
			return
		}
		defer f.Close()

		info, err := f.Stat()
		if err != nil {
			logger.Error("local avatar stat failed", "avatar_id", id, "error", err)
			writeError(w, http.StatusInternalServerError, "failed to read avatar")
			return
		}
		// No stored content-type: http.ServeContent falls back to sniffing
		// the first 512 bytes when the name's extension (".img", chosen
		// precisely so it never matches a real mime type) doesn't resolve
		// to one — correct for whichever image format was actually
		// uploaded, without this handler needing to track it separately.
		http.ServeContent(w, r, id+".img", info.ModTime(), f)
	}
}

func profileJSON(p *profile.Profile) map[string]any {
	m := map[string]any{
		"id":                         p.ID,
		"handle":                     p.Handle,
		"role":                       p.Role,
		"is_moderator":               p.IsModerator,
		"is_verified_artist":         p.IsVerifiedArtist,
		"is_minor_performer_account": p.IsMinorPerformerAccount,
		"sevak_count":                p.SevakCount,
		// Leads the response on purpose — see internal/profile.Profile's
		// own doc on why reuse count, not follower count, is this
		// profile's headline metric.
		"total_reuse_count":   p.TotalReuseCount,
		"viewer_is_following": p.ViewerIsFollowing,
		// Always present, even empty — migration 000015's own columns
		// default to '{}', not NULL, so there's no nil-slice case to
		// special-case the way the *string fields below need.
		"languages":   p.Languages,
		"instruments": p.Instruments,
	}
	if p.DisplayName != nil {
		m["display_name"] = *p.DisplayName
	}
	if p.AvatarURL != nil {
		m["avatar_url"] = *p.AvatarURL
	}
	if p.Bio != nil {
		m["bio"] = *p.Bio
	}
	if p.Tradition != nil {
		m["tradition"] = *p.Tradition
	}
	if p.Lineage != nil {
		m["lineage"] = *p.Lineage
	}
	return m
}
