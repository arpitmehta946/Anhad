// Package audio implements the reel-derived half of the audio library
// (docs/PRD.md §7.3, migration 000013 wiring into the audio_library table
// migration 000003 first created): every reel's audio becomes a reusable,
// attributed track the moment the reel clears moderation — never before,
// the same "nothing unmoderated is reusable" rule internal/reels.ListFeed
// already enforces for the video feed itself.
//
// "Use this sound" (finalizing a new reel from a track) lives in
// internal/reels instead of here, alongside CreateReel/CreateJugalbandi —
// it's a reel-creation path first and an audio-reuse event second, the
// same reasoning that keeps CreateJugalbandi in internal/reels rather than
// in a package named after the thing being duetted with.
package audio

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/anhad/api/internal/store"
)

// ErrTrackNotFound means the given track id doesn't exist — used by
// RecordPlay; internal/reels.Service.CreateFromAudioTrack does its own
// lookup and has its own sentinel for the same underlying miss, since the
// caller-facing error differs by context.
var ErrTrackNotFound = errors.New("audio track not found")

// Track is a row from audio_library (migrations 000003, 000013), joined
// with its creator's display name so the library browser never needs a
// second round trip — same shape decision as internal/reels.Reel.
// SourceReelID is nil for a seeded/curated track (docs/PRD.md §7.3's
// still-unbuilt other P0 half); every reel-derived track has one.
type Track struct {
	ID                 string
	SourceReelID       *string
	CreatorID          string
	CreatorDisplayName *string
	AudioURL           string
	Category           string
	Title              *string
	IsPublic           bool
	ReuseCount         int64
	PlayCount          int64
	CreatedAt          time.Time
}

type Service struct {
	store  *store.Store
	source AudioSource
}

func NewService(st *store.Store, source AudioSource) *Service {
	return &Service{store: st, source: source}
}

// PublishTrackForReel makes reelID's own audio reusable — called by
// internal/moderation exactly once, the moment a reel first becomes
// approved. Idempotent via ON CONFLICT DO NOTHING against
// audio_library.source_reel_id's own UNIQUE constraint: a reel only ever
// transitions to approved once in practice (internal/moderation.RunAndSave's
// own WHERE ... moderation_status = 'pending' guard, and actOnReport's
// WHERE ... IN ('pending', 'held')), but a retried background task
// shouldn't be able to violate that assumption and publish a duplicate row.
//
// is_public resolves from the reel's own audio_library_enabled column
// (set at reel-creation time in internal/reels.CreateReel) — not decided
// here, since by the time a reel is approved its creator's choice (or a
// minor-performer account's own default-off, docs/PRD.md §4.5) is already
// fixed on the row.
func (s *Service) PublishTrackForReel(ctx context.Context, reelID string) error {
	var creatorID, videoURL, category string
	var caption *string
	var libraryEnabled bool
	err := s.store.PG.QueryRow(ctx,
		`SELECT creator_id, video_url, category, caption, audio_library_enabled FROM reels WHERE id = $1`,
		reelID,
	).Scan(&creatorID, &videoURL, &category, &caption, &libraryEnabled)
	if err != nil {
		// Including pgx.ErrNoRows: this is only ever called with a reelID
		// that was just approved in the same request/task, so a missing
		// row here means something is genuinely wrong, not an expected
		// "not found yet" case worth its own sentinel.
		return fmt.Errorf("load reel: %w", err)
	}

	audioURL, err := s.source.ExtractFromReel(ctx, videoURL)
	if err != nil {
		return fmt.Errorf("extract audio: %w", err)
	}

	_, err = s.store.PG.Exec(ctx,
		`INSERT INTO audio_library (source_reel_id, artist_id, r2_url, category, title, is_public)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 ON CONFLICT (source_reel_id) DO NOTHING`,
		reelID, creatorID, audioURL, category, caption, libraryEnabled,
	)
	if err != nil {
		return fmt.Errorf("insert audio_library row: %w", err)
	}
	return nil
}

// ListLibrary returns public tracks, newest first, optionally filtered to
// one category — same cursor-on-created_at shape as
// internal/reels.Service.ListFeed and the same reasoning: an append-mostly,
// never-reordered list is exactly what a cursor, not an offset, is for.
//
// creatorID scopes this same listing to one creator's own tracks — the
// profile page's sound-library tab reuses this endpoint rather than
// needing its own.
func (s *Service) ListLibrary(ctx context.Context, category, creatorID *string, before *time.Time, limit int) ([]*Track, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	const query = `
		SELECT t.id, t.source_reel_id, t.artist_id, u.display_name, t.r2_url,
		       t.category, t.title, t.is_public, t.reuse_count, t.play_count, t.created_at
		FROM audio_library t
		JOIN users u ON u.id = t.artist_id
		WHERE t.is_public
		  AND ($1::text IS NULL OR t.category = $1)
		  AND ($2::timestamptz IS NULL OR t.created_at < $2)
		  AND ($4::uuid IS NULL OR t.artist_id = $4)
		ORDER BY t.created_at DESC
		LIMIT $3
	`
	rows, err := s.store.PG.Query(ctx, query, category, before, limit, creatorID)
	if err != nil {
		return nil, fmt.Errorf("list library: %w", err)
	}
	defer rows.Close()

	tracks := make([]*Track, 0, limit)
	for rows.Next() {
		var t Track
		if err := rows.Scan(
			&t.ID, &t.SourceReelID, &t.CreatorID, &t.CreatorDisplayName, &t.AudioURL,
			&t.Category, &t.Title, &t.IsPublic, &t.ReuseCount, &t.PlayCount, &t.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan track: %w", err)
		}
		tracks = append(tracks, &t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list library: %w", err)
	}
	return tracks, nil
}

// RecordPlay increments a track's play_count — the raw signal the future
// royalty batch job (docs/PRD.md §10.4) will divide the monthly pool by.
// No auth required to call this (same as the feed itself being free to
// browse): a play is a play whether or not the listener has an account.
func (s *Service) RecordPlay(ctx context.Context, trackID string) error {
	tag, err := s.store.PG.Exec(ctx,
		`UPDATE audio_library SET play_count = play_count + 1 WHERE id = $1`, trackID,
	)
	if err != nil {
		return fmt.Errorf("record play: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrTrackNotFound
	}
	return nil
}
