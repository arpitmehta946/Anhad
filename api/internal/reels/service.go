// Package reels implements the first feed slice (docs/PRD.md §4.1, §7.1):
// upload (via a pre-signed-URL-style VideoStorage), and a reverse-
// chronological, category-filterable feed of already-moderated reels. The
// moderation pipeline itself (docs/PRD.md §8) is a later slice — every
// reel created here starts and stays PENDING until something outside this
// package advances it, which is exactly why ListFeed only ever returns
// approved rows.
package reels

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/anhad/api/internal/store"
)

// Categories is the mandatory upload category list (docs/PRD.md §4.1,
// resolved August 18 2026) — Katha/Discourse is deliberately absent
// (dropped from scope), not an oversight.
var Categories = []string{
	"bhajan", "mantra", "stuti", "chalisa", "aarti", "kirtan", "sant_vani", "meditation_naad",
}

var (
	// ErrInvalidCategory means the caller passed a category outside
	// Categories — the database CHECK constraint would catch this too,
	// but rejecting it before a query round-trip gives a clearer error.
	ErrInvalidCategory = errors.New("category must be one of: bhajan, mantra, stuti, chalisa, aarti, kirtan, sant_vani, meditation_naad")
	// ErrUploadNotReady means videoID either doesn't exist or hasn't
	// finished uploading yet — VideoStorage.PlaybackURL reported not
	// ready. Distinct from a generic error so the handler can return 409
	// rather than 500.
	ErrUploadNotReady = errors.New("upload not found or not finished yet")
)

// Reel is a row from the reels table (db/migrations/000004,
// 000007) — only the columns this slice actually reads or writes; the
// engagement counters exist in the schema but nothing here touches them
// yet.
type Reel struct {
	ID               string
	CreatorID        string
	VideoURL         string
	Caption          *string
	Category         string
	ModerationStatus string
	CreatedAt        time.Time
}

// Service implements reel upload and the public feed read. Role
// enforcement ("only creators can upload," docs/PRD.md's own instruction)
// happens one layer up, in the HTTP middleware
// (internal/server/reels.go's requireRole) — this mirrors how JWT
// validity itself is checked in requireAuth and never re-verified here,
// not a gap in this package.
type Service struct {
	store   *store.Store
	storage VideoStorage
}

func NewService(st *store.Store, storage VideoStorage) *Service {
	return &Service{store: st, storage: storage}
}

// CreateUploadTarget hands back a fresh upload target for a creator to
// upload a video to, before any reel row exists — see UploadTarget's doc
// for exactly what "never writes directly to storage" means here.
func (s *Service) CreateUploadTarget(ctx context.Context) (*UploadTarget, error) {
	return s.storage.CreateUploadTarget(ctx)
}

// CreateReel finalizes an upload into a real reel: validates the category,
// confirms videoID's upload actually finished, and inserts the row —
// always PENDING (the column default), never chosen by the caller, since
// nothing this slice does is allowed to grant itself approval.
func (s *Service) CreateReel(ctx context.Context, creatorID, videoID, category string, caption *string) (*Reel, error) {
	if !isValidCategory(category) {
		return nil, ErrInvalidCategory
	}

	videoURL, ready, err := s.storage.PlaybackURL(ctx, videoID)
	if err != nil {
		return nil, fmt.Errorf("check upload status: %w", err)
	}
	if !ready {
		return nil, ErrUploadNotReady
	}

	const query = `
		INSERT INTO reels (creator_id, video_url, category, caption)
		VALUES ($1, $2, $3, $4)
		RETURNING id, creator_id, video_url, caption, category, moderation_status, created_at
	`
	var reel Reel
	err = s.store.PG.QueryRow(ctx, query, creatorID, videoURL, category, caption).Scan(
		&reel.ID, &reel.CreatorID, &reel.VideoURL, &reel.Caption, &reel.Category,
		&reel.ModerationStatus, &reel.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("insert reel: %w", err)
	}
	return &reel, nil
}

// ListFeed returns approved reels, newest first, optionally filtered to
// one category — never ranked (docs/PRD.md's explicit instruction: "no
// ranking algorithm"), just the moderation-gated chronological order the
// partial indexes in migrations 000004/000007 are built for.
//
// Cursor-paginated on created_at: pass the last item's CreatedAt as
// before to get the next page, nil for the first page. Deliberately not
// offset-paginated — an offset silently skips or repeats rows if new
// reels land between page requests, which a cursor on an append-mostly,
// never-reordered feed doesn't.
func (s *Service) ListFeed(ctx context.Context, category *string, before *time.Time, limit int) ([]*Reel, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	const query = `
		SELECT id, creator_id, video_url, caption, category, moderation_status, created_at
		FROM reels
		WHERE moderation_status = 'approved'
		  AND ($1::text IS NULL OR category = $1)
		  AND ($2::timestamptz IS NULL OR created_at < $2)
		ORDER BY created_at DESC
		LIMIT $3
	`
	rows, err := s.store.PG.Query(ctx, query, category, before, limit)
	if err != nil {
		return nil, fmt.Errorf("list feed: %w", err)
	}
	defer rows.Close()

	reels := make([]*Reel, 0, limit)
	for rows.Next() {
		var reel Reel
		if err := rows.Scan(
			&reel.ID, &reel.CreatorID, &reel.VideoURL, &reel.Caption, &reel.Category,
			&reel.ModerationStatus, &reel.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan reel: %w", err)
		}
		reels = append(reels, &reel)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list feed: %w", err)
	}
	return reels, nil
}

func isValidCategory(category string) bool {
	for _, c := range Categories {
		if c == category {
			return true
		}
	}
	return false
}
