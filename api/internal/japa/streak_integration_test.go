package japa

import (
	"context"
	"log/slog"
	"os"
	"testing"
	"time"

	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/store"
)

// TestStreakIntegration seeds several days of japa_sessions history for a
// throwaway user — including a gap day — directly via SQL (bypassing the
// anti-cheat path entirely, which is appropriate for backdating test data
// that couldn't have been submitted live), then drives the exact same
// UpdateStreakForDate production code calls, verifying the resulting
// japa_streaks row and the day-21 Seva Pass grant. Skips rather than fails
// if the local Postgres/Redis from docker-compose aren't reachable, since
// this isn't wired into a CI DB yet.
func TestStreakIntegration(t *testing.T) {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	st, err := store.Connect(ctx, cfg.DatabaseURL, cfg.RedisURL)
	if err != nil {
		t.Skipf("local postgres/redis not reachable, skipping: %v", err)
	}
	// Registered before the user-delete cleanup below, so it runs after —
	// t.Cleanup unwinds LIFO. A plain `defer st.Close()` would instead run
	// as soon as the test function returns, which is *before* any
	// t.Cleanup callbacks fire, closing the pool out from under the
	// delete-test-user cleanup.
	t.Cleanup(st.Close)

	svc := NewService(st, slog.New(slog.NewTextHandler(os.Stderr, nil)))

	var userID string
	err = st.PG.QueryRow(ctx, `
		INSERT INTO users (phone_number, display_name) VALUES ($1, 'Streak Test')
		RETURNING id
	`, "+919999900001").Scan(&userID)
	if err != nil {
		t.Fatalf("seed test user: %v", err)
	}
	t.Cleanup(func() {
		if _, err := st.PG.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID); err != nil {
			t.Errorf("cleanup test user: %v", err)
		}
	})

	// A base date far enough in the past that "today" in nextStreak's
	// day-21 reward check can never collide with real activity.
	base := time.Date(2020, 1, 1, 12, 0, 0, 0, time.UTC)
	seedDay := func(offset int, taps int) {
		day := base.AddDate(0, 0, offset)
		_, err := st.PG.Exec(ctx, `
			INSERT INTO japa_sessions (user_id, tap_count, started_at, ended_at)
			VALUES ($1, $2, $3, $3)
		`, userID, taps, day)
		if err != nil {
			t.Fatalf("seed day %d: %v", offset, err)
		}
		if err := svc.UpdateStreakForDate(ctx, userID, day); err != nil {
			t.Fatalf("update streak for day %d: %v", offset, err)
		}
	}

	assertStreak := func(label string, wantCurrent, wantLongest int) {
		t.Helper()
		streak, err := svc.GetStreak(ctx, userID)
		if err != nil {
			t.Fatalf("%s: get streak: %v", label, err)
		}
		if streak.CurrentStreak != wantCurrent || streak.LongestStreak != wantLongest {
			t.Errorf("%s: streak = {current: %d, longest: %d}, want {current: %d, longest: %d}",
				label, streak.CurrentStreak, streak.LongestStreak, wantCurrent, wantLongest)
		}
	}

	// Day 0: first qualifying day.
	seedDay(0, malaThreshold)
	assertStreak("day 0", 1, 1)

	// Day 1: a sub-threshold day must NOT count or break the streak build-up —
	// UpdateStreakForDate itself is a no-op below the threshold.
	seedDay(1, malaThreshold-1)
	assertStreak("day 1 (below threshold)", 1, 1)

	// Day 2: consecutive qualifying day extends it. (Day 1 stays
	// unqualified since its total is still below threshold — the gap is
	// between day 0 and day 2's *qualifying* activity.)
	seedDay(2, malaThreshold)
	assertStreak("day 2", 1, 1) // day1->day2 gap is 1 day but day1 never qualified, so last_chanted_date was day0 -> gap of 2 -> restart

	// Days 3, 4: consecutive qualifying days now build cleanly off day 2.
	seedDay(3, malaThreshold)
	assertStreak("day 3", 2, 2)
	seedDay(4, malaThreshold)
	assertStreak("day 4", 3, 3)

	// Day 6: skip day 5 entirely (a real gap) — streak must break, longest
	// must survive as history rather than resetting to 0.
	seedDay(6, malaThreshold)
	assertStreak("day 6 (after a missed day)", 1, 3)

	// Multiple batches landing the same day must not double-count: calling
	// UpdateStreakForDate again for day 6 with more taps that same day
	// should leave the streak unchanged.
	if err := svc.UpdateStreakForDate(ctx, userID, base.AddDate(0, 0, 6).Add(2*time.Hour)); err != nil {
		t.Fatalf("re-apply day 6: %v", err)
	}
	assertStreak("day 6 (re-applied same day)", 1, 3)

	// Build days 7..26 consecutively (20 more days on top of day 6's streak
	// of 1) to cross the day-21 reward threshold exactly at day 26.
	for offset := 7; offset <= 26; offset++ {
		seedDay(offset, malaThreshold)
	}
	assertStreak("day 26 (streak of 21)", 21, 21)

	var subCount int
	err = st.PG.QueryRow(ctx, `
		SELECT count(*) FROM user_subscriptions
		WHERE user_id = $1 AND plan = 'seva_pass' AND source = 'streak_reward' AND status = 'trialing'
	`, userID).Scan(&subCount)
	if err != nil {
		t.Fatalf("check streak reward subscription: %v", err)
	}
	if subCount != 1 {
		t.Errorf("expected exactly 1 streak-reward seva_pass subscription after reaching day 21, got %d", subCount)
	}

	var trialEndsAt time.Time
	err = st.PG.QueryRow(ctx, `
		SELECT trial_ends_at FROM user_subscriptions
		WHERE user_id = $1 AND source = 'streak_reward'
	`, userID).Scan(&trialEndsAt)
	if err != nil {
		t.Fatalf("read trial_ends_at: %v", err)
	}
	if d := time.Until(trialEndsAt); d < 6*24*time.Hour || d > 8*24*time.Hour {
		t.Errorf("trial_ends_at = %v (%.1f days from now), want ~7 days", trialEndsAt, d.Hours()/24)
	}

	// Day 27 continues past 21 — must not grant a second trial.
	seedDay(27, malaThreshold)
	err = st.PG.QueryRow(ctx, `
		SELECT count(*) FROM user_subscriptions
		WHERE user_id = $1 AND plan = 'seva_pass' AND source = 'streak_reward'
	`, userID).Scan(&subCount)
	if err != nil {
		t.Fatalf("recheck streak reward subscription: %v", err)
	}
	if subCount != 1 {
		t.Errorf("continuing past day 21 must not grant a second trial, got %d subscription rows", subCount)
	}
}
