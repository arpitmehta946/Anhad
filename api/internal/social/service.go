// Package social implements the P0 renamed interactions from docs/PRD.md
// §6/§7.2: Pranam (like), Satsang (comment), Prasad (share), Smaran (save),
// Sevak (follow). Jugalbandi (remix/duet, P1) and the long-press Pranam
// reaction variants Shanti/Gyaan/Kripa (P2) are deliberately not built here
// — see PRD.md §7.2's own priority split.
package social

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/anhad/api/internal/store"
)

var (
	ErrReelNotFound = errors.New("reel not found")
	// ErrCreatorNotFound covers both "no such user" and "that user isn't a
	// creator" — Sevak is explicitly "joining a creator's circle"
	// (docs/PRD.md §6), not a general viewer-to-viewer follow, so the
	// caller doesn't need to distinguish the two cases.
	ErrCreatorNotFound  = errors.New("creator not found")
	ErrCannotFollowSelf = errors.New("you can't follow yourself")
	ErrCommentEmpty     = errors.New("comment cannot be empty")
	// ErrCommentTooLong's exact limit depends on the reel creator's
	// comments_mode (maxCommentLenReflectionOnly vs maxCommentLenOpen) —
	// wrapped with the actual number in PostSatsang rather than fixed in
	// the sentinel string.
	ErrCommentTooLong = errors.New("comment is too long")
)

// maxCommentLenReflectionOnly/maxCommentLenOpen are the one concrete,
// enforced difference between the two comments_mode values in this slice —
// see the migration's own comment on satsang_comments for why: no
// reply/thread feature exists yet to gate more meaningfully than this. A
// shorter cap in reflection_only mode nudges toward a brief reflection
// rather than an argument, which is the actual thing "discourage debate"
// (docs/PRD.md §6) asks for.
const (
	maxCommentLenReflectionOnly = 280
	maxCommentLenOpen           = 500
)

type Comment struct {
	ID              string
	ReelID          string
	UserID          string
	UserDisplayName *string
	Body            string
	CreatedAt       time.Time
}

type Service struct {
	store *store.Store
}

func NewService(st *store.Store) *Service {
	return &Service{store: st}
}

// TogglePranam inserts or deletes this viewer's pranams row for reelID —
// present means "un-pranam," absent means "pranam" — and keeps
// reels.like_count in sync in the same transaction, so a reader never sees
// a count that disagrees with whether their own row exists.
func (s *Service) TogglePranam(ctx context.Context, userID, reelID string) (active bool, count int64, err error) {
	return s.toggleReelEngagement(ctx, "pranams", "like_count", userID, reelID)
}

// ToggleSmaran is TogglePranam's exact mirror against smarans/save_count —
// same toggle-by-presence shape, different table.
func (s *Service) ToggleSmaran(ctx context.Context, userID, reelID string) (active bool, count int64, err error) {
	return s.toggleReelEngagement(ctx, "smarans", "save_count", userID, reelID)
}

// toggleReelEngagement is the shared transaction behind TogglePranam and
// ToggleSmaran: both are "one row per (reel, user) in some join table, kept
// in lockstep with a counter column on reels" with nothing else different
// between them, so this is the one place that logic is written rather than
// duplicated per interaction. table/countColumn are only ever passed as the
// two compile-time-known constants above, never caller input, so building
// the query string with fmt.Sprintf here doesn't open a SQL-injection path.
func (s *Service) toggleReelEngagement(ctx context.Context, table, countColumn, userID, reelID string) (active bool, count int64, err error) {
	tx, err := s.store.PG.Begin(ctx)
	if err != nil {
		return false, 0, fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op if already committed

	deleteQuery := fmt.Sprintf(`DELETE FROM %s WHERE reel_id = $1 AND user_id = $2`, table)
	tag, err := tx.Exec(ctx, deleteQuery, reelID, userID)
	if err != nil {
		return false, 0, fmt.Errorf("delete %s: %w", table, err)
	}

	if tag.RowsAffected() > 0 {
		active = false
		decrementQuery := fmt.Sprintf(
			`UPDATE reels SET %s = %s - 1 WHERE id = $1 RETURNING %s`, countColumn, countColumn, countColumn,
		)
		if err := tx.QueryRow(ctx, decrementQuery, reelID).Scan(&count); err != nil {
			return false, 0, fmt.Errorf("decrement %s: %w", countColumn, err)
		}
	} else {
		active = true
		insertQuery := fmt.Sprintf(`INSERT INTO %s (reel_id, user_id) VALUES ($1, $2)`, table)
		if _, err := tx.Exec(ctx, insertQuery, reelID, userID); err != nil {
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.Code == "23503" { // foreign_key_violation
				return false, 0, ErrReelNotFound
			}
			return false, 0, fmt.Errorf("insert %s: %w", table, err)
		}
		incrementQuery := fmt.Sprintf(
			`UPDATE reels SET %s = %s + 1 WHERE id = $1 RETURNING %s`, countColumn, countColumn, countColumn,
		)
		if err := tx.QueryRow(ctx, incrementQuery, reelID).Scan(&count); err != nil {
			return false, 0, fmt.Errorf("increment %s: %w", countColumn, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return false, 0, fmt.Errorf("commit: %w", err)
	}
	return active, count, nil
}

// ToggleSevak inserts or deletes a sevaks row — present means "already
// following," absent means "not following." Unlike Pranam/Smaran there's no
// counter column to keep in step here in this slice (no follower-count
// display exists yet), so this is a plain toggle, not a transaction.
func (s *Service) ToggleSevak(ctx context.Context, followerID, creatorID string) (active bool, error error) {
	if followerID == creatorID {
		return false, ErrCannotFollowSelf
	}

	tag, err := s.store.PG.Exec(ctx,
		`DELETE FROM sevaks WHERE follower_id = $1 AND creator_id = $2`, followerID, creatorID,
	)
	if err != nil {
		return false, fmt.Errorf("delete sevak: %w", err)
	}
	if tag.RowsAffected() > 0 {
		return false, nil
	}

	var role string
	err = s.store.PG.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, creatorID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrCreatorNotFound
	}
	if err != nil {
		return false, fmt.Errorf("load creator role: %w", err)
	}
	if role != "creator" {
		return false, ErrCreatorNotFound
	}

	if _, err := s.store.PG.Exec(ctx,
		`INSERT INTO sevaks (follower_id, creator_id) VALUES ($1, $2)`, followerID, creatorID,
	); err != nil {
		return false, fmt.Errorf("insert sevak: %w", err)
	}
	return true, nil
}

// RecordPrasad increments a reel's share_count. Deliberately not a
// per-user toggle like Pranam/Smaran — "distributing something blessed"
// (docs/PRD.md §6) is a repeatable act (sharing the same reel to two
// different people is two real shares), not a one-time state, so there's no
// "un-share" and no unique-per-user row to check.
func (s *Service) RecordPrasad(ctx context.Context, reelID string) (int64, error) {
	var count int64
	err := s.store.PG.QueryRow(ctx,
		`UPDATE reels SET share_count = share_count + 1 WHERE id = $1 RETURNING share_count`, reelID,
	).Scan(&count)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrReelNotFound
	}
	if err != nil {
		return 0, fmt.Errorf("record prasad: %w", err)
	}
	return count, nil
}

// PostSatsang validates and inserts a comment, enforcing whichever length
// cap the reel creator's own comments_mode implies (see the const doc
// above), and keeps reels.comment_count in step.
func (s *Service) PostSatsang(ctx context.Context, userID, reelID, body string) (*Comment, error) {
	trimmed := strings.TrimSpace(body)
	if trimmed == "" {
		return nil, ErrCommentEmpty
	}

	var commentsMode string
	err := s.store.PG.QueryRow(ctx,
		`SELECT u.comments_mode FROM reels r JOIN users u ON u.id = r.creator_id WHERE r.id = $1`, reelID,
	).Scan(&commentsMode)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrReelNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("load comments mode: %w", err)
	}

	maxLen := maxCommentLenOpen
	if commentsMode == "reflection_only" {
		maxLen = maxCommentLenReflectionOnly
	}
	if len(trimmed) > maxLen {
		return nil, fmt.Errorf("%w: max %d characters", ErrCommentTooLong, maxLen)
	}

	tx, err := s.store.PG.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op if already committed

	var c Comment
	err = tx.QueryRow(ctx,
		`INSERT INTO satsang_comments (reel_id, user_id, body) VALUES ($1, $2, $3)
		 RETURNING id, reel_id, user_id, body, created_at`,
		reelID, userID, trimmed,
	).Scan(&c.ID, &c.ReelID, &c.UserID, &c.Body, &c.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("insert satsang comment: %w", err)
	}
	if _, err := tx.Exec(ctx,
		`UPDATE reels SET comment_count = comment_count + 1 WHERE id = $1`, reelID,
	); err != nil {
		return nil, fmt.Errorf("increment comment count: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	var displayName *string
	if err := s.store.PG.QueryRow(ctx, `SELECT display_name FROM users WHERE id = $1`, userID).Scan(&displayName); err == nil {
		c.UserDisplayName = displayName
	}
	return &c, nil
}

// ListSatsang returns comments oldest-first — a Satsang is read as a
// stream of individual reflections (docs/FRONTEND_GUIDELINES.md §7), not a
// most-recent-first debate thread. Cursor-paginated on created_at, the same
// shape as reels.Service.ListFeed.
func (s *Service) ListSatsang(ctx context.Context, reelID string, after *time.Time, limit int) ([]*Comment, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	const query = `
		SELECT c.id, c.reel_id, c.user_id, u.display_name, c.body, c.created_at
		FROM satsang_comments c
		JOIN users u ON u.id = c.user_id
		WHERE c.reel_id = $1 AND ($2::timestamptz IS NULL OR c.created_at > $2)
		ORDER BY c.created_at ASC
		LIMIT $3
	`
	rows, err := s.store.PG.Query(ctx, query, reelID, after, limit)
	if err != nil {
		return nil, fmt.Errorf("list satsang: %w", err)
	}
	defer rows.Close()

	comments := make([]*Comment, 0, limit)
	for rows.Next() {
		var c Comment
		if err := rows.Scan(&c.ID, &c.ReelID, &c.UserID, &c.UserDisplayName, &c.Body, &c.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan satsang comment: %w", err)
		}
		comments = append(comments, &c)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list satsang: %w", err)
	}
	return comments, nil
}

// ViewerState reports, for one signed-in viewer, which of reelIDs they've
// already pranam'd/smaran'd and which of creatorIDs they already sevak. One
// batched read per feed page rather than a per-reel round trip, so
// scrolling doesn't fan out into dozens of tiny queries — the feed handler
// calls this once with every reel/creator id on the page it's about to
// return.
func (s *Service) ViewerState(ctx context.Context, viewerID string, reelIDs, creatorIDs []string) (pranamed, smaraned, following map[string]bool, err error) {
	pranamed = map[string]bool{}
	smaraned = map[string]bool{}
	following = map[string]bool{}

	if len(reelIDs) > 0 {
		if err := scanIDSet(ctx, s.store, pranamed,
			`SELECT reel_id FROM pranams WHERE user_id = $1 AND reel_id = ANY($2)`, viewerID, reelIDs); err != nil {
			return nil, nil, nil, fmt.Errorf("load pranam state: %w", err)
		}
		if err := scanIDSet(ctx, s.store, smaraned,
			`SELECT reel_id FROM smarans WHERE user_id = $1 AND reel_id = ANY($2)`, viewerID, reelIDs); err != nil {
			return nil, nil, nil, fmt.Errorf("load smaran state: %w", err)
		}
	}
	if len(creatorIDs) > 0 {
		if err := scanIDSet(ctx, s.store, following,
			`SELECT creator_id FROM sevaks WHERE follower_id = $1 AND creator_id = ANY($2)`, viewerID, creatorIDs); err != nil {
			return nil, nil, nil, fmt.Errorf("load sevak state: %w", err)
		}
	}
	return pranamed, smaraned, following, nil
}

func scanIDSet(ctx context.Context, st *store.Store, into map[string]bool, query string, args ...any) error {
	rows, err := st.PG.Query(ctx, query, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return err
		}
		into[id] = true
	}
	return rows.Err()
}
