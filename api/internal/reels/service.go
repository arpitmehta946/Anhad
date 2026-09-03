// Package reels implements the first feed slice (docs/PRD.md §4.1, §7.1):
// upload (via a pre-signed-URL-style VideoStorage), and a reverse-
// chronological, category-filterable feed of already-moderated reels.
// Every reel created here starts PENDING and is advanced by
// internal/moderation's async pipeline (enqueued at the end of
// CreateReel) to either APPROVED or HELD, never by this package directly
// — which is exactly why ListFeed only ever returns approved rows.
package reels

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

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
	// ErrSourceReelNotFound/ErrSourceReelNotApproved/ErrJugalbandiDisabled
	// are CreateJugalbandi's own sentinels — a Jugalbandi can only be
	// recorded against a reel that exists, has already cleared moderation
	// (duetting on a pending/held/rejected reel makes no sense — there's
	// nothing publicly playable to duet against yet), and hasn't had
	// Jugalbandi turned off by its own creator (docs/PRD.md §4.5, §7.2).
	ErrSourceReelNotFound    = errors.New("reel not found")
	ErrSourceReelNotApproved = errors.New("this reel isn't published yet")
	ErrJugalbandiDisabled    = errors.New("the creator has turned off Jugalbandi for this reel")
)

// Reel is a row from the reels table (db/migrations/000004, 000007,
// 000010, 000011), joined with just enough of its creator's own row
// (display name, comments_mode) that the feed and reel-detail responses
// don't need a second round trip per reel. The four engagement counters
// are read here now (internal/social keeps them in step with the
// pranams/smarans/satsang_comments tables and share_count/save_count),
// though writing them is entirely internal/social's job, not this
// package's.
//
// The Jugalbandi* fields are only ever non-nil/non-zero for a reel that IS
// a duet result (JugalbandiSourceID set) — ListFeed's own query joins the
// source reel and its creator so a client can render the side-by-side
// duet and attribute both creators without a second round trip.
type Reel struct {
	ID                                 string
	CreatorID                          string
	CreatorDisplayName                 *string
	VideoURL                           string
	Caption                            *string
	Category                           string
	ModerationStatus                   string
	CreatorCommentsMode                string
	PranamCount                        int64
	SatsangCount                       int64
	PrasadCount                        int64
	SmaranCount                        int64
	JugalbandiEnabled                  bool
	JugalbandiReuseCount               int64
	JugalbandiSourceID                 *string
	JugalbandiSourceVideoURL           *string
	JugalbandiSourceCaption            *string
	JugalbandiSourceCreatorID          *string
	JugalbandiSourceCreatorDisplayName *string
	CreatedAt                          time.Time
}

// Service implements reel upload and the public feed read. Role
// enforcement ("only creators can upload," docs/PRD.md's own instruction)
// happens one layer up, in the HTTP middleware
// (internal/server/reels.go's requireRole) — this mirrors how JWT
// validity itself is checked in requireAuth and never re-verified here,
// not a gap in this package.
// ModerationEnqueuer kicks off the async three-layer moderation pipeline
// (docs/PRD.md §8.1) for a newly created reel — implemented by
// internal/moderation.AsynqEnqueuer. Defined here rather than importing
// internal/moderation directly, the same decoupling VideoStorage already
// gives this package from whichever real storage backend is live.
type ModerationEnqueuer interface {
	EnqueueClassifyReel(ctx context.Context, reelID, videoURL string) error
}

type Service struct {
	store    *store.Store
	storage  VideoStorage
	enqueuer ModerationEnqueuer
	logger   *slog.Logger
}

func NewService(st *store.Store, storage VideoStorage, enqueuer ModerationEnqueuer, logger *slog.Logger) *Service {
	return &Service{store: st, storage: storage, enqueuer: enqueuer, logger: logger}
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
//
// jugalbandiEnabled is the creator's own explicit choice for this one reel
// (docs/PRD.md §4.5/§7.2) — nil means "use the default for this creator,"
// which insertReel resolves to false for a minor-performer (Family)
// account and true otherwise. A non-nil value always wins regardless of
// account type: an ordinary adult creator can turn Jugalbandi off same as
// anyone; a Family Account's parent — the only person who can ever be
// authenticated as that account, see db/migrations/000011's own doc — can
// turn it on the same way, which is what "only the parent can enable it"
// actually means here: there is no separate permission gate to build
// beyond "the account holder controls their own reel's settings," since a
// minor performer never holds their own login in this design.
func (s *Service) CreateReel(ctx context.Context, creatorID, videoID, category string, caption *string, jugalbandiEnabled *bool) (*Reel, error) {
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

	return s.insertReel(ctx, creatorID, videoURL, category, caption, jugalbandiEnabled, nil)
}

// CreateJugalbandi finalizes an upload into a duet result: the same
// validation as CreateReel, plus checking the source reel is real,
// published, and still open to duets, and — in the same transaction as
// the insert — bumping the source's own jugalbandi_reuse_count (docs/PRD.md
// §7.3's "audio-reuse counter visible to the original artist," the
// reel-level half of it; see migration 000011's own doc for why it isn't
// audio_library-keyed yet).
func (s *Service) CreateJugalbandi(ctx context.Context, creatorID, sourceReelID, videoID, category string, caption *string) (*Reel, error) {
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

	var sourceStatus string
	var sourceJugalbandiEnabled bool
	err = s.store.PG.QueryRow(ctx,
		`SELECT moderation_status, jugalbandi_enabled FROM reels WHERE id = $1`, sourceReelID,
	).Scan(&sourceStatus, &sourceJugalbandiEnabled)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrSourceReelNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("load source reel: %w", err)
	}
	if sourceStatus != "approved" {
		return nil, ErrSourceReelNotApproved
	}
	if !sourceJugalbandiEnabled {
		return nil, ErrJugalbandiDisabled
	}

	tx, err := s.store.PG.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op if already committed

	reel, err := s.insertReelTx(ctx, tx, creatorID, videoURL, category, caption, nil, &sourceReelID)
	if err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx,
		`UPDATE reels SET jugalbandi_reuse_count = jugalbandi_reuse_count + 1 WHERE id = $1`, sourceReelID,
	); err != nil {
		return nil, fmt.Errorf("increment jugalbandi reuse count: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	// Best-effort, same as CreateReel — see its own doc for why a queue
	// hiccup here doesn't fail an otherwise-successful upload request.
	if err := s.enqueuer.EnqueueClassifyReel(ctx, reel.ID, reel.VideoURL); err != nil {
		s.logger.Error("failed to enqueue moderation pipeline", "reel_id", reel.ID, "error", err)
	}

	return reel, nil
}

func (s *Service) insertReel(
	ctx context.Context, creatorID, videoURL, category string, caption *string,
	jugalbandiEnabled *bool, jugalbandiSourceID *string,
) (*Reel, error) {
	reel, err := s.insertReelTx(ctx, s.store.PG, creatorID, videoURL, category, caption, jugalbandiEnabled, jugalbandiSourceID)
	if err != nil {
		return nil, err
	}

	// Best-effort: the reel is already durably PENDING at this point, so a
	// queue hiccup here shouldn't fail an otherwise-successful upload
	// request (the client would read that as "upload failed" and could
	// retry, creating a duplicate reel). A PENDING reel that never gets
	// enqueued just sits unmoderated rather than being lost — a real gap,
	// worth a periodic sweep eventually, but not one this request should
	// pay for.
	if err := s.enqueuer.EnqueueClassifyReel(ctx, reel.ID, reel.VideoURL); err != nil {
		s.logger.Error("failed to enqueue moderation pipeline", "reel_id", reel.ID, "error", err)
	}

	return reel, nil
}

// dbTX is the subset of pgxpool.Pool/pgx.Tx insertReelTx needs — lets
// CreateJugalbandi run this insert inside its own transaction (so the
// reuse-count bump commits atomically with it) while CreateReel runs it
// as a plain pool query, without duplicating the query itself.
type dbTX interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// insertReelTx is CreateReel/CreateJugalbandi's shared insert: the CTE,
// rather than a plain INSERT...RETURNING, is what lets this still come
// back with the creator's real display_name/comments_mode in one round
// trip — a plain RETURNING can't reach into users. jugalbandiEnabled nil
// resolves to NOT is_minor_performer_account for the creator's own row
// (see CreateReel's doc); the four engagement counts and the Jugalbandi
// source-attribution fields aren't selected from anywhere: a reel this
// request just inserted genuinely has none of the former yet, and only
// ever has the latter when jugalbandiSourceID is set, which the caller
// already knows.
func (s *Service) insertReelTx(
	ctx context.Context, tx dbTX, creatorID, videoURL, category string, caption *string,
	jugalbandiEnabled *bool, jugalbandiSourceID *string,
) (*Reel, error) {
	const query = `
		WITH inserted AS (
			INSERT INTO reels (creator_id, video_url, category, caption, jugalbandi_enabled, jugalbandi_source_id)
			VALUES (
				$1, $2, $3, $4,
				COALESCE($5, NOT (SELECT is_minor_performer_account FROM users WHERE id = $1)),
				$6
			)
			RETURNING id, creator_id, video_url, caption, category, moderation_status, created_at,
			          jugalbandi_enabled, jugalbandi_source_id
		)
		SELECT inserted.id, inserted.creator_id, u.display_name, inserted.video_url, inserted.caption,
		       inserted.category, inserted.moderation_status, u.comments_mode, inserted.created_at,
		       inserted.jugalbandi_enabled, inserted.jugalbandi_source_id
		FROM inserted
		JOIN users u ON u.id = inserted.creator_id
	`
	var reel Reel
	err := tx.QueryRow(ctx, query, creatorID, videoURL, category, caption, jugalbandiEnabled, jugalbandiSourceID).Scan(
		&reel.ID, &reel.CreatorID, &reel.CreatorDisplayName, &reel.VideoURL, &reel.Caption, &reel.Category,
		&reel.ModerationStatus, &reel.CreatorCommentsMode, &reel.CreatedAt,
		&reel.JugalbandiEnabled, &reel.JugalbandiSourceID,
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

	// The two LEFT JOINs (never INNER — most reels aren't a Jugalbandi
	// result, and jugalbandi_source_id being NULL must still return the
	// row) pull in the source reel's own video/caption and its creator's
	// identity, so a client can render the side-by-side duet and
	// attribute both creators without a second request per Jugalbandi
	// reel (docs/PRD.md §7.2).
	const query = `
		SELECT r.id, r.creator_id, u.display_name, r.video_url, r.caption, r.category,
		       r.moderation_status, u.comments_mode,
		       r.like_count, r.comment_count, r.share_count, r.save_count,
		       r.jugalbandi_enabled, r.jugalbandi_reuse_count, r.jugalbandi_source_id,
		       src.video_url, src.caption, src.creator_id, src_creator.display_name,
		       r.created_at
		FROM reels r
		JOIN users u ON u.id = r.creator_id
		LEFT JOIN reels src ON src.id = r.jugalbandi_source_id
		LEFT JOIN users src_creator ON src_creator.id = src.creator_id
		WHERE r.moderation_status = 'approved'
		  AND ($1::text IS NULL OR r.category = $1)
		  AND ($2::timestamptz IS NULL OR r.created_at < $2)
		ORDER BY r.created_at DESC
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
			&reel.ID, &reel.CreatorID, &reel.CreatorDisplayName, &reel.VideoURL, &reel.Caption, &reel.Category,
			&reel.ModerationStatus, &reel.CreatorCommentsMode,
			&reel.PranamCount, &reel.SatsangCount, &reel.PrasadCount, &reel.SmaranCount,
			&reel.JugalbandiEnabled, &reel.JugalbandiReuseCount, &reel.JugalbandiSourceID,
			&reel.JugalbandiSourceVideoURL, &reel.JugalbandiSourceCaption,
			&reel.JugalbandiSourceCreatorID, &reel.JugalbandiSourceCreatorDisplayName,
			&reel.CreatedAt,
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
