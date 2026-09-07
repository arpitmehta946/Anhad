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

	"github.com/jackc/pgx/v5"

	"github.com/anhad/api/internal/store"
)

// ErrTrackNotFound means the given track id doesn't exist — used by
// RecordPlay; internal/reels.Service.CreateFromAudioTrack does its own
// lookup and has its own sentinel for the same underlying miss, since the
// caller-facing error differs by context.
var ErrTrackNotFound = errors.New("audio track not found")

// platformAudioCategories mirrors internal/reels.Categories exactly
// (docs/PRD.md §4.1's fixed list, also enforced by the
// audio_library_category_check constraint) — duplicated rather than
// imported since internal/reels doesn't export its own list and importing
// internal/reels into internal/audio for one constant would invert the
// dependency the other direction already goes (reels reaches into
// audio_library by raw SQL, not through this package's Go types).
var platformAudioCategories = map[string]bool{
	"bhajan": true, "mantra": true, "stuti": true, "chalisa": true,
	"aarti": true, "kirtan": true, "sant_vani": true, "meditation_naad": true,
}

// Track is a row from audio_library (migrations 000003, 000013, 000016),
// joined with its creator's display name so the library browser never
// needs a second round trip — same shape decision as internal/reels.Reel.
// SourceReelID is nil for a seeded/curated track; every reel-derived track
// has one.
//
// CreatorID/CreatorDisplayName are nil exactly when IsPlatformTrack is
// true (migration 000016's own CHECK constraint enforces that these two
// facts never disagree) — a platform track (a tanpura drone, a temple
// bell) isn't anyone's performance, so there's no artist row to join
// against at all, not just an anonymous or unnamed one.
type Track struct {
	ID                 string
	SourceReelID       *string
	CreatorID          *string
	CreatorDisplayName *string
	AudioURL           string
	Category           string
	Title              *string
	IsPublic           bool
	IsPlatformTrack    bool
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
		       t.category, t.title, t.is_public, t.is_platform_track,
		       t.reuse_count, t.play_count, t.created_at
		FROM audio_library t
		LEFT JOIN users u ON u.id = t.artist_id
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
			&t.Category, &t.Title, &t.IsPublic, &t.IsPlatformTrack,
			&t.ReuseCount, &t.PlayCount, &t.CreatedAt,
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

// ErrInvalidCategory means SeedPlatformTrack was asked to insert a category
// outside docs/PRD.md §4.1's fixed list — checked here too, not just left
// to the audio_library_category_check constraint, so cmd/seedaudio can
// report a clear per-track error against its manifest rather than an
// opaque Postgres constraint-violation message.
var ErrInvalidCategory = errors.New("category must be one of: bhajan, mantra, stuti, chalisa, aarti, kirtan, sant_vani, meditation_naad")

// SeedPlatformTrack inserts or updates one platform-owned track (a tanpura
// drone, a temple bell — docs/PRD.md §7.3 P0, IMPLEMENTATION_PLAN.md
// Phase 3) — always public, always bypassing the moderation pipeline
// entirely (there's no reel, and nothing to moderate: cmd/seedaudio is the
// only caller, run by a developer against a source recording they
// themselves vetted), and always with no artist row (see Track's own doc
// on why NULL beats a fake "Anhad" user).
//
// Idempotent by (is_platform_track, title): re-running cmd/seedaudio
// against an updated manifest — a re-recorded tanpura drone, a corrected
// title — updates the existing row's audio/category/deity/raga rather than
// accumulating a duplicate. title doesn't have a database-level UNIQUE
// constraint (a reel-derived track's own title is free-text, taken from
// its caption, and two reels can share a caption), so this checks first
// rather than using ON CONFLICT — acceptable for a low-volume admin tool
// invoked sequentially by one developer, not a concurrent-write path.
func (s *Service) SeedPlatformTrack(ctx context.Context, category, title, audioURL string, deity, raga *string) (id string, created bool, err error) {
	if !platformAudioCategories[category] {
		return "", false, ErrInvalidCategory
	}

	err = s.store.PG.QueryRow(ctx,
		`SELECT id FROM audio_library WHERE is_platform_track AND title = $1`, title,
	).Scan(&id)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		err = s.store.PG.QueryRow(ctx,
			`INSERT INTO audio_library
			    (artist_id, r2_url, category, title, deity, raga, is_public, is_platform_track)
			 VALUES (NULL, $1, $2, $3, $4, $5, true, true)
			 RETURNING id`,
			audioURL, category, title, deity, raga,
		).Scan(&id)
		if err != nil {
			return "", false, fmt.Errorf("insert platform track: %w", err)
		}
		return id, true, nil
	case err != nil:
		return "", false, fmt.Errorf("check existing platform track: %w", err)
	default:
		_, err = s.store.PG.Exec(ctx,
			`UPDATE audio_library SET r2_url = $1, category = $2, deity = $3, raga = $4, is_public = true
			 WHERE id = $5`,
			audioURL, category, deity, raga, id,
		)
		if err != nil {
			return "", false, fmt.Errorf("update platform track: %w", err)
		}
		return id, false, nil
	}
}
