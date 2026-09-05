// Package profile implements creator profile pages — the destination
// Sevak (follow, docs/PRD.md §6) previously had none: following a creator
// led nowhere to actually visit. A profile is deliberately not a new
// concept bolted onto users; it's a read (and, for your own account, a
// write) over columns users already had plus the few this package's own
// migration (000014) added — handle, bio, is_verified_artist.
package profile

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/anhad/api/internal/store"
)

const maxBioLength = 160

var (
	ErrProfileNotFound = errors.New("profile not found")
	ErrBioTooLong      = errors.New("bio must be 160 characters or fewer")
)

// Profile is a user's public-facing profile — everything a visitor to
// /v1/users/{id}/profile sees. SevakCount is a live COUNT over the sevaks
// table (migration 000010), not a denormalized counter — this endpoint is
// nowhere near hot enough (a profile view, not a per-reel action) to need
// one. ViewerIsFollowing is only meaningful when the request carried a
// bearer token for someone other than this profile's own owner; the HTTP
// handler is responsible for not asking otherwise.
type Profile struct {
	ID                      string
	Handle                  string
	DisplayName             *string
	AvatarURL               *string
	Bio                     *string
	Role                    string
	IsModerator             bool
	IsVerifiedArtist        bool
	IsMinorPerformerAccount bool
	SevakCount              int64
	ViewerIsFollowing       bool
}

type Service struct {
	store  *store.Store
	avatar AvatarStorage
}

func NewService(st *store.Store, avatar AvatarStorage) *Service {
	return &Service{store: st, avatar: avatar}
}

// GetProfile loads userID's profile, backfilling a handle first if this
// account predates migration 000014 or was created since without one
// (every account creation path today still just does phone-OTP signup —
// see internal/auth.findOrCreateUser — which has no handle-choosing step
// of its own). Generating one lazily, on first profile view, means that
// step doesn't need to exist yet for profiles to work: nothing about
// choosing your own handle is built, so a real, unique, functional default
// stands in for it, the same "real column, no chooser UI yet" shape this
// package's migration already uses for is_verified_artist.
//
// viewerID is the caller's own id, if authenticated — nil for an
// anonymous viewer, and also expected to be nil (by the HTTP handler, not
// re-checked here) when it would just equal userID, since "am I following
// myself" isn't a real question.
func (s *Service) GetProfile(ctx context.Context, userID string, viewerID *string) (*Profile, error) {
	p, err := s.loadProfile(ctx, userID)
	if err != nil {
		return nil, err
	}

	if p.Handle == "" {
		handle, err := s.backfillHandle(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("backfill handle: %w", err)
		}
		p.Handle = handle
	}

	if err := s.store.PG.QueryRow(ctx,
		`SELECT count(*) FROM sevaks WHERE creator_id = $1`, userID,
	).Scan(&p.SevakCount); err != nil {
		return nil, fmt.Errorf("count sevaks: %w", err)
	}

	if viewerID != nil {
		if err := s.store.PG.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM sevaks WHERE follower_id = $1 AND creator_id = $2)`,
			*viewerID, userID,
		).Scan(&p.ViewerIsFollowing); err != nil {
			return nil, fmt.Errorf("check viewer following: %w", err)
		}
	}

	return p, nil
}

func (s *Service) loadProfile(ctx context.Context, userID string) (*Profile, error) {
	const query = `
		SELECT id, coalesce(handle, ''), display_name, avatar_url, bio,
		       role, is_moderator, is_verified_artist, is_minor_performer_account
		FROM users WHERE id = $1
	`
	var p Profile
	err := s.store.PG.QueryRow(ctx, query, userID).Scan(
		&p.ID, &p.Handle, &p.DisplayName, &p.AvatarURL, &p.Bio,
		&p.Role, &p.IsModerator, &p.IsVerifiedArtist, &p.IsMinorPerformerAccount,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrProfileNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("load profile: %w", err)
	}
	return &p, nil
}

// backfillHandle generates a random, unique handle and persists it —
// retried a handful of times against the (astronomically unlikely, at 8
// random hex characters) chance of a collision, the same defensive shape
// as other id-generation in this codebase rather than trusting the odds
// alone.
func (s *Service) backfillHandle(ctx context.Context, userID string) (string, error) {
	for attempt := 0; attempt < 5; attempt++ {
		handle, err := randomHandle()
		if err != nil {
			return "", err
		}
		tag, err := s.store.PG.Exec(ctx,
			`UPDATE users SET handle = $1 WHERE id = $2 AND handle IS NULL`, handle, userID,
		)
		if err != nil {
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.ConstraintName == "users_handle_key" {
				continue // collision — try another
			}
			return "", err
		}
		if tag.RowsAffected() > 0 {
			return handle, nil
		}
		// RowsAffected == 0 with no error means another request already
		// backfilled this same user's handle between our load and this
		// update — read back whatever it landed on rather than treating
		// that as a failure.
		var existing string
		if err := s.store.PG.QueryRow(ctx,
			`SELECT handle FROM users WHERE id = $1`, userID,
		).Scan(&existing); err != nil {
			return "", err
		}
		return existing, nil
	}
	return "", fmt.Errorf("could not generate a unique handle after 5 attempts")
}

func randomHandle() (string, error) {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return "devotee_" + hex.EncodeToString(b), nil
}

// UpdateProfile changes the fields their own owner is allowed to change —
// display name and bio. Handle and is_verified_artist aren't editable
// here: the former has no chooser UI yet (see GetProfile's own doc), and
// the latter is a moderator/admin-granted marker, never self-declared.
//
// Unlike internal/reels.CreateReel's optional fields, both arguments here
// are plain strings, not pointers: this is a full profile-edit form, not a
// sparse patch, so the caller always submits its current values for both —
// an empty string means "clear it," not "leave unchanged," which is
// exactly what an edit form needs (a caption at *creation* time has no
// prior value to preserve, so nil-means-omitted is the right shape there;
// a bio being *edited* does, so this needs the opposite).
func (s *Service) UpdateProfile(ctx context.Context, userID, displayName, bio string) (*Profile, error) {
	if len(bio) > maxBioLength {
		return nil, ErrBioTooLong
	}

	var displayNamePtr, bioPtr *string
	if displayName != "" {
		displayNamePtr = &displayName
	}
	if bio != "" {
		bioPtr = &bio
	}

	if _, err := s.store.PG.Exec(ctx,
		`UPDATE users SET display_name = $2, bio = $3 WHERE id = $1`,
		userID, displayNamePtr, bioPtr,
	); err != nil {
		return nil, fmt.Errorf("update profile: %w", err)
	}

	return s.GetProfile(ctx, userID, nil)
}

// SaveAvatar stores r as userID's new avatar and returns the refreshed
// profile.
func (s *Service) SaveAvatar(ctx context.Context, userID string, r io.Reader) (*Profile, error) {
	url, err := s.avatar.Save(ctx, r)
	if err != nil {
		return nil, fmt.Errorf("save avatar: %w", err)
	}
	if _, err := s.store.PG.Exec(ctx,
		`UPDATE users SET avatar_url = $1 WHERE id = $2`, url, userID,
	); err != nil {
		return nil, fmt.Errorf("update avatar_url: %w", err)
	}
	return s.GetProfile(ctx, userID, nil)
}
