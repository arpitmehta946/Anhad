// Package moderation implements in-app reporting and the moderator queue
// that acts on it (docs/PRD.md §7.8, §8.4; docs/GAPS.md 🔴 "No in-app
// reporting mechanism" and 🟡 "No admin audit log") — required under
// India's IT Rules 2021 (docs/PRD.md §3.4, §9.3) now that users can post
// content, not optional polish.
package moderation

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/anhad/api/internal/store"
)

// AudioLibrary is the narrow interface this package depends on to make a
// newly-approved reel's audio reusable (docs/PRD.md §7.3) — implemented by
// internal/audio.Service. Defined here rather than importing internal/audio
// directly, the same decoupling this package already has from
// internal/reels via reels.ModerationEnqueuer.
type AudioLibrary interface {
	PublishTrackForReel(ctx context.Context, reelID string) error
}

// Reasons is the fixed report-reason list. docs/PRD.md §8.0.1 names
// financial_solicitation and medical_miracle_claim explicitly as the
// under-addressed harms this platform's structural rules don't otherwise
// catch; not_devotional and filmi_commercial back the category/audio
// checks (§8.1, §8.2); hate_speech covers the Satsang-comment risk §8.0.1
// itself flags; other is a deliberate catch-all rather than forcing a
// false-precision choice. pipeline_uncertain is never chosen by a human
// reporter (SubmitReport rejects it via isValidReason below) — it's what
// the moderation pipeline itself files (reporter_id NULL, pipeline.go's
// RunAndSave) when a reel fails or can't confidently pass the classifier.
var Reasons = []string{
	"not_devotional", "filmi_commercial", "financial_solicitation",
	"medical_miracle_claim", "hate_speech", "other",
}

const reasonPipelineUncertain = "pipeline_uncertain"

var (
	ErrInvalidReason = errors.New(
		"reason must be one of: not_devotional, filmi_commercial, financial_solicitation, medical_miracle_claim, hate_speech, other",
	)
	// ErrAlreadyReported means this reporter already has a report on file
	// for this reel — db/migrations/000008's UNIQUE(reporter_id, reel_id)
	// enforces this at the database level; this just gives it a friendlier
	// error than a raw constraint-violation 500.
	ErrAlreadyReported = errors.New("you have already reported this reel")
	// ErrRateLimited means this reporter has filed too many reports too
	// fast — the Redis-backed brake on mass-reporting (docs/PRD.md §12
	// "sectarian brigading policy"). Distinct from ErrAlreadyReported: this
	// one is about velocity across *different* reels, which the unique
	// constraint alone doesn't touch.
	ErrRateLimited    = errors.New("too many reports submitted recently, try again later")
	ErrReelNotFound   = errors.New("reel not found")
	ErrReportNotFound = errors.New("report not found")
	// ErrReportNotOpen means a moderator tried to act on a report that's
	// already actioned or dismissed — acting twice would double-log the
	// audit trail for one real decision.
	ErrReportNotOpen = errors.New("report has already been reviewed")
)

const (
	// reportRateLimitWindow/maxReportsPerWindow bound how fast one account
	// can file reports at all, regardless of which reels — the
	// UNIQUE(reporter_id, reel_id) constraint alone only stops re-reporting
	// the *same* reel, not fanning out across many different creators'
	// content quickly, which is the actual shape a brigading attempt takes.
	reportRateLimitWindow = time.Hour
	maxReportsPerWindow   = 20
)

// Report is a row from the reports table (db/migrations/000008,
// db/migrations/000009). ReporterID is nil for a system-generated report
// the moderation pipeline filed (reason = pipeline_uncertain) rather than
// a human — see reasonPipelineUncertain and pipeline.go's RunAndSave.
type Report struct {
	ID         string
	ReporterID *string
	ReelID     string
	Reason     string
	Detail     *string
	Status     string
	CreatedAt  time.Time
}

// QueueItem is an open report joined with just enough about the reported
// reel for a moderator to review it without a second round trip. The
// ReelModeration* fields are only ever non-nil for a pipeline-filed
// report (Report.ReporterID == nil) — a human report's reel may or may
// not have pipeline detail depending on when it was uploaded, but the
// fields are always there in the response shape either way so the
// mobile client doesn't need two response types.
type QueueItem struct {
	Report
	ReelVideoURL              string
	ReelCaption               *string
	ReelCategory              string
	ReelCreatorID             string
	ReelModerationTranscript  *string
	ReelModerationLabel       *string
	ReelModerationReason      *string
	ReelModerationFingerprint *string
}

// AuditLogEntry is a row from moderation_audit_log — every moderator
// action, on whatever it acted on, why (docs/GAPS.md's 🟡 audit-log gap;
// also an IT Rules 2021 requirement).
type AuditLogEntry struct {
	ID          string
	ModeratorID string
	ReportID    *string
	ReelID      string
	Action      string
	Reason      *string
	CreatedAt   time.Time
}

type Service struct {
	store  *store.Store
	audio  AudioLibrary
	logger *slog.Logger
}

func NewService(st *store.Store, audio AudioLibrary, logger *slog.Logger) *Service {
	return &Service{store: st, audio: audio, logger: logger}
}

// SubmitReport files a report against a reel. Always lands status=open;
// a reporter can never set anything else, the same way a creator can
// never set a reel's own moderation_status (internal/reels.CreateReel).
func (s *Service) SubmitReport(ctx context.Context, reporterID, reelID, reason string, detail *string) (*Report, error) {
	if !isValidReason(reason) {
		return nil, ErrInvalidReason
	}

	limited, err := s.checkRateLimit(ctx, reporterID)
	if err != nil {
		return nil, fmt.Errorf("check rate limit: %w", err)
	}
	if limited {
		return nil, ErrRateLimited
	}

	const query = `
		INSERT INTO reports (reporter_id, reel_id, reason, detail)
		VALUES ($1, $2, $3, $4)
		RETURNING id, reporter_id, reel_id, reason, detail, status, created_at
	`
	var report Report
	err = s.store.PG.QueryRow(ctx, query, reporterID, reelID, reason, detail).Scan(
		&report.ID, &report.ReporterID, &report.ReelID, &report.Reason, &report.Detail,
		&report.Status, &report.CreatedAt,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) {
			switch pgErr.ConstraintName {
			case "reports_reporter_id_reel_id_key":
				return nil, ErrAlreadyReported
			case "reports_reel_id_fkey":
				return nil, ErrReelNotFound
			}
		}
		return nil, fmt.Errorf("insert report: %w", err)
	}
	return &report, nil
}

// checkRateLimit implements a fixed-window Redis counter — simpler than
// japa's sliding-window rate limit (internal/japa's checkRateLimitWindow)
// because report abuse doesn't need per-second precision, just a velocity
// cap. INCR on a key that doesn't exist yet creates it at 1; the EXPIRE is
// only set on that first increment so the window doesn't keep sliding
// forward on every subsequent report within it.
func (s *Service) checkRateLimit(ctx context.Context, reporterID string) (bool, error) {
	key := "ratelimit:reports:" + reporterID
	count, err := s.store.Redis.Incr(ctx, key).Result()
	if err != nil {
		return false, err
	}
	if count == 1 {
		if err := s.store.Redis.Expire(ctx, key, reportRateLimitWindow).Err(); err != nil {
			return false, err
		}
	}
	return count > maxReportsPerWindow, nil
}

// ListQueue returns open reports, oldest first (first reported, first
// reviewed — no ranking, matching the feed's own "no algorithm" stance),
// joined with the reported reel's own details.
func (s *Service) ListQueue(ctx context.Context, limit int) ([]*QueueItem, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	const query = `
		SELECT r.id, r.reporter_id, r.reel_id, r.reason, r.detail, r.status, r.created_at,
		       reels.video_url, reels.caption, reels.category, reels.creator_id,
		       reels.moderation_transcript, reels.moderation_classifier_label,
		       reels.moderation_classifier_reason, reels.moderation_fingerprint_match
		FROM reports r
		JOIN reels ON reels.id = r.reel_id
		WHERE r.status = 'open'
		ORDER BY r.created_at ASC
		LIMIT $1
	`
	rows, err := s.store.PG.Query(ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("list queue: %w", err)
	}
	defer rows.Close()

	items := make([]*QueueItem, 0, limit)
	for rows.Next() {
		var item QueueItem
		if err := rows.Scan(
			&item.ID, &item.ReporterID, &item.ReelID, &item.Reason, &item.Detail,
			&item.Status, &item.CreatedAt,
			&item.ReelVideoURL, &item.ReelCaption, &item.ReelCategory, &item.ReelCreatorID,
			&item.ReelModerationTranscript, &item.ReelModerationLabel,
			&item.ReelModerationReason, &item.ReelModerationFingerprint,
		); err != nil {
			return nil, fmt.Errorf("scan queue item: %w", err)
		}
		items = append(items, &item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list queue: %w", err)
	}
	return items, nil
}

// DismissReport marks a report reviewed with no action taken against the
// reel — the report itself may still have been mistaken, sectarian, or
// simply not a real violation. Logs the decision either way.
//
// For a reel the moderation pipeline held (or one that's still plain
// 'pending'), dismissing is what actually publishes it — "no violation
// here" on a not-yet-approved reel means it should become approved, the
// same call a moderator reviewing a pipeline-flagged upload is making.
// For a reel already 'approved' (the ordinary user-report case), this is
// a no-op on the reel itself. It never touches an already-'rejected' reel
// — dismissing an unrelated later report can't un-reject something a
// moderator already took down.
func (s *Service) DismissReport(ctx context.Context, moderatorID, reportID string, reason *string) error {
	return s.actOnReport(ctx, moderatorID, reportID, "report_dismissed", reason, false)
}

// RemoveReel actions the report by taking the reel down (moderation_status
// = 'rejected', the same status value the async pipeline would eventually
// reach for the same content — this is the human backstop docs/PRD.md
// §8.4 describes acting early) and marks the report actioned.
func (s *Service) RemoveReel(ctx context.Context, moderatorID, reportID string, reason *string) error {
	return s.actOnReport(ctx, moderatorID, reportID, "reel_removed", reason, true)
}

// actOnReport is the shared transaction behind DismissReport/RemoveReel:
// load the report locked FOR UPDATE (so two moderators racing the same
// report can't both "win"), reject if it's not open anymore, apply the
// reel-status change if this action calls for one, flip the report's own
// status, and write the audit log entry — all one commit, so a partial
// failure never leaves the report actioned without a trail explaining why.
func (s *Service) actOnReport(ctx context.Context, moderatorID, reportID, action string, reason *string, removeReel bool) error {
	tx, err := s.store.PG.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op if already committed

	var reelID, status string
	err = tx.QueryRow(ctx,
		`SELECT reel_id, status FROM reports WHERE id = $1 FOR UPDATE`, reportID,
	).Scan(&reelID, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrReportNotFound
	}
	if err != nil {
		return fmt.Errorf("load report: %w", err)
	}
	if status != "open" {
		return ErrReportNotOpen
	}

	reportStatus := "dismissed"
	justApproved := false
	if removeReel {
		reportStatus = "actioned"
		if _, err := tx.Exec(ctx,
			`UPDATE reels SET moderation_status = 'rejected' WHERE id = $1`, reelID,
		); err != nil {
			return fmt.Errorf("reject reel: %w", err)
		}
		// A reel already published to the library (it was 'approved' before
		// this later report took it down) must stop being reusable too —
		// hidden, not deleted, so reels that already used this track via
		// "use this sound" (docs/PRD.md §7.3) keep their own attribution
		// and reuse/play history intact.
		if _, err := tx.Exec(ctx,
			`UPDATE audio_library SET is_public = false WHERE source_reel_id = $1`, reelID,
		); err != nil {
			return fmt.Errorf("hide audio track: %w", err)
		}
	} else {
		tag, err := tx.Exec(ctx,
			`UPDATE reels SET moderation_status = 'approved' WHERE id = $1 AND moderation_status IN ('pending', 'held')`,
			reelID,
		)
		if err != nil {
			return fmt.Errorf("approve reel: %w", err)
		}
		justApproved = tag.RowsAffected() > 0
	}

	if _, err := tx.Exec(ctx,
		`UPDATE reports SET status = $1 WHERE id = $2`, reportStatus, reportID,
	); err != nil {
		return fmt.Errorf("update report status: %w", err)
	}

	if _, err := tx.Exec(ctx,
		`INSERT INTO moderation_audit_log (moderator_id, report_id, reel_id, action, reason)
		 VALUES ($1, $2, $3, $4, $5)`,
		moderatorID, reportID, reelID, action, reason,
	); err != nil {
		return fmt.Errorf("write audit log: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit: %w", err)
	}

	// Best-effort and after commit, same reasoning as
	// internal/reels.Service's own moderation-enqueue calls: the report
	// decision is already durably recorded at this point, so a failure
	// here shouldn't turn a successful moderator action into an error —
	// it would just leave this one reel's audio unpublished a little
	// longer than intended, self-healing on the next successful call.
	if justApproved {
		if err := s.audio.PublishTrackForReel(ctx, reelID); err != nil {
			s.logger.Error("failed to publish audio track", "reel_id", reelID, "error", err)
		}
	}
	return nil
}

// ListAuditLog returns moderator actions, newest first — the verifiable
// "who acted on what, when, why" trail IT Rules 2021 and basic
// multi-moderator accountability both require.
func (s *Service) ListAuditLog(ctx context.Context, limit int) ([]*AuditLogEntry, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}

	const query = `
		SELECT id, moderator_id, report_id, reel_id, action, reason, created_at
		FROM moderation_audit_log
		ORDER BY created_at DESC
		LIMIT $1
	`
	rows, err := s.store.PG.Query(ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("list audit log: %w", err)
	}
	defer rows.Close()

	entries := make([]*AuditLogEntry, 0, limit)
	for rows.Next() {
		var entry AuditLogEntry
		if err := rows.Scan(
			&entry.ID, &entry.ModeratorID, &entry.ReportID, &entry.ReelID,
			&entry.Action, &entry.Reason, &entry.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan audit log entry: %w", err)
		}
		entries = append(entries, &entry)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list audit log: %w", err)
	}
	return entries, nil
}

func isValidReason(reason string) bool {
	for _, r := range Reasons {
		if r == reason {
			return true
		}
	}
	return false
}
