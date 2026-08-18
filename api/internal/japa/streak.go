package japa

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	// malaThreshold is one full mala (docs/PRD.md §7.4) — the minimum a
	// calendar day needs to reach to count toward the streak.
	malaThreshold = 108

	// streakRewardDays is the PRD.md §10.3 threshold: this many consecutive
	// qualifying days unlocks a Seva Pass trial.
	streakRewardDays = 21

	// streakRewardTrialDays is the trial length itself — never permanent
	// (PRD.md §10.3), enforced again by user_subscriptions' own CHECK
	// constraint on streak_reward rows.
	streakRewardTrialDays = 7
)

// Streak is a user's current standing, read from japa_streaks.
type Streak struct {
	CurrentStreak   int
	LongestStreak   int
	LastChantedDate *time.Time
}

// GetStreak reads the user's streak state. A user who has never completed a
// full mala in a day has no row yet — that's a zero-value Streak, not an
// error.
func (s *Service) GetStreak(ctx context.Context, userID string) (*Streak, error) {
	const query = `
		SELECT current_streak, longest_streak, last_chanted_date
		FROM japa_streaks WHERE user_id = $1
	`
	var streak Streak
	err := s.store.PG.QueryRow(ctx, query, userID).
		Scan(&streak.CurrentStreak, &streak.LongestStreak, &streak.LastChantedDate)
	if errors.Is(err, pgx.ErrNoRows) {
		return &Streak{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get japa streak: %w", err)
	}
	return &streak, nil
}

// UpdateStreakForDate recomputes this user's streak contribution for a
// single calendar day from that day's cumulative total in japa_sessions,
// applying it to japa_streaks if the day qualifies (>= malaThreshold taps)
// and hasn't already been counted. Always re-derives the day's total from
// source rather than trusting an incremental delta, so it's safe to call
// more than once for the same day (every batch flush that day calls this
// again) and safe to call out of the normal SubmitTaps flow entirely —
// which is what lets tests seed several days of history, including a gap,
// and drive the exact same streak logic production traffic uses.
func (s *Service) UpdateStreakForDate(ctx context.Context, userID string, date time.Time) error {
	day := civilDate(date)

	tx, err := s.store.PG.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin streak update tx: %w", err)
	}
	defer tx.Rollback(ctx) // no-op once Commit succeeds

	var dayTotal int
	const totalQuery = `
		SELECT COALESCE(SUM(tap_count), 0) FROM japa_sessions
		WHERE user_id = $1 AND started_at >= $2 AND started_at < $2 + INTERVAL '1 day'
	`
	if err := tx.QueryRow(ctx, totalQuery, userID, day).Scan(&dayTotal); err != nil {
		return fmt.Errorf("sum japa taps for date: %w", err)
	}
	if dayTotal < malaThreshold {
		return nil
	}

	if err := s.applyStreakDay(ctx, tx, userID, day); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit streak update tx: %w", err)
	}
	return nil
}

// applyStreakDay locks the user's streak row (INSERT ... ON CONFLICT DO
// UPDATE is a no-op update, but still takes the row lock, same as SELECT ...
// FOR UPDATE would) so two batch flushes landing close together — e.g. a
// backlog of several queued sessions syncing at once on reconnect — can't
// both read the same stale current_streak and double-increment it.
func (s *Service) applyStreakDay(ctx context.Context, tx pgx.Tx, userID string, day time.Time) error {
	var current, longest int
	var lastChanted *time.Time
	err := tx.QueryRow(ctx, `
		INSERT INTO japa_streaks (user_id) VALUES ($1)
		ON CONFLICT (user_id) DO UPDATE SET user_id = japa_streaks.user_id
		RETURNING current_streak, longest_streak, last_chanted_date
	`, userID).Scan(&current, &longest, &lastChanted)
	if err != nil {
		return fmt.Errorf("lock japa streak: %w", err)
	}

	if lastChanted != nil && sameDate(*lastChanted, day) {
		// Already counted today (an earlier batch this same day already
		// crossed the threshold and applied it) — idempotent no-op.
		return nil
	}

	newCurrent, newLongest := nextStreak(current, longest, lastChanted, day)
	if _, err := tx.Exec(ctx, `
		UPDATE japa_streaks
		SET current_streak = $1, longest_streak = $2, last_chanted_date = $3
		WHERE user_id = $4
	`, newCurrent, newLongest, day, userID); err != nil {
		return fmt.Errorf("update japa streak: %w", err)
	}

	if newCurrent == streakRewardDays {
		if err := grantStreakReward(ctx, tx, userID); err != nil {
			return fmt.Errorf("grant streak reward: %w", err)
		}
	}
	return nil
}

// nextStreak decides how today folds into the running streak: unbroken
// (yesterday counted) extends it by one, anything else — no prior day, or a
// gap of two or more days — restarts it at 1, since today itself just
// qualified. longest is only ever raised, never lowered, so it survives a
// later reset (docs/PRD.md §7.4: "longest streak is preserved as history").
func nextStreak(current, longest int, lastChanted *time.Time, today time.Time) (newCurrent, newLongest int) {
	switch {
	case lastChanted == nil:
		newCurrent = 1
	case daysBetween(*lastChanted, today) == 1:
		newCurrent = current + 1
	default:
		newCurrent = 1
	}
	newLongest = longest
	if newCurrent > newLongest {
		newLongest = newCurrent
	}
	return newCurrent, newLongest
}

// grantStreakReward unlocks the PRD.md §10.3 reward: a 7-day Seva Pass
// trial, never a permanent unlock. Skips granting if the user already has
// an active or trialing Seva Pass (purchased, or from an earlier streak) —
// the reward is meant to be a bounded trial, not something that stacks
// indefinitely across repeated 21-day streaks.
func grantStreakReward(ctx context.Context, tx pgx.Tx, userID string) error {
	var existing int
	err := tx.QueryRow(ctx, `
		SELECT count(*) FROM user_subscriptions
		WHERE user_id = $1 AND plan = 'seva_pass' AND status IN ('trialing', 'active')
	`, userID).Scan(&existing)
	if err != nil {
		return fmt.Errorf("check existing seva pass: %w", err)
	}
	if existing > 0 {
		return nil
	}

	// trial_ends_at is derived from the same now() as created_at's own
	// DEFAULT, both evaluated within this one INSERT's transaction — using
	// Go's time.Now() for one side and Postgres's now() for the other (via
	// the DEFAULT) risked the two clocks disagreeing enough to trip the
	// table's own "trial_ends_at <= created_at + 7 days" CHECK constraint,
	// exactly the kind of clock-skew race the constraint exists to catch.
	_, err = tx.Exec(ctx, `
		INSERT INTO user_subscriptions (user_id, plan, status, source, trial_ends_at)
		VALUES ($1, 'seva_pass', 'trialing', 'streak_reward', now() + make_interval(days => $2))
	`, userID, streakRewardTrialDays)
	if err != nil {
		return fmt.Errorf("insert streak reward subscription: %w", err)
	}
	return nil
}

// civilDate truncates to a UTC calendar date. The streak's notion of "day"
// is UTC, not the user's local timezone — users has no timezone column yet,
// and the japa_sessions timestamps this is derived from are already
// absolute instants, so UTC is the only definition the server can apply
// consistently without guessing at a device's clock.
func civilDate(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func sameDate(a, b time.Time) bool {
	return civilDate(a).Equal(civilDate(b))
}

func daysBetween(a, b time.Time) int {
	return int(civilDate(b).Sub(civilDate(a)).Hours() / 24)
}
