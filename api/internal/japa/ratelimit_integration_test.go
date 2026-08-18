package japa

import (
	"context"
	"errors"
	"log/slog"
	"math/rand"
	"os"
	"testing"
	"time"

	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/store"
)

// humanTaps generates n strictly-increasing timestamps ending at end, spread
// out enough to pass checkRate/checkUniformity (real human variance, not a
// fixed interval) while averaging roughly ratePerMinute.
func humanTaps(n int, end time.Time, ratePerMinute float64) []time.Time {
	r := rand.New(rand.NewSource(1))
	meanInterval := time.Duration(float64(time.Minute) / ratePerMinute)
	taps := make([]time.Time, n)
	t := end
	for i := n - 1; i >= 0; i-- {
		taps[i] = t
		// +/- 40% jitter around the mean interval — comfortably clears the
		// uniformity floor without changing the average pace much.
		jitter := 1 + (r.Float64()-0.5)*0.8
		t = t.Add(-time.Duration(float64(meanInterval) * jitter))
	}
	return taps
}

func TestRateLimitIntegration(t *testing.T) {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	st, err := store.Connect(ctx, cfg.DatabaseURL, cfg.RedisURL)
	if err != nil {
		t.Skipf("local postgres/redis not reachable, skipping: %v", err)
	}
	t.Cleanup(st.Close)

	svc := NewService(st, slog.New(slog.NewTextHandler(os.Stderr, nil)))

	newUser := func(phone string) string {
		var userID string
		err := st.PG.QueryRow(ctx, `
			INSERT INTO users (phone_number, display_name) VALUES ($1, 'Rate Limit Test')
			RETURNING id
		`, phone).Scan(&userID)
		if err != nil {
			t.Fatalf("seed test user: %v", err)
		}
		t.Cleanup(func() {
			if _, err := st.PG.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID); err != nil {
				t.Errorf("cleanup test user %s: %v", phone, err)
			}
		})
		return userID
	}

	t.Run("a large offline backlog submitted as one batch is never rate-limited", func(t *testing.T) {
		userID := newUser("+919999900002")
		// 600 taps spread realistically over the last 20 real minutes,
		// ending well outside the 60-second rate-limit window — exactly
		// the "chanted for 20 minutes with no signal, then reconnected"
		// scenario. 600 alone exceeds maxTapsPerMinute, which is exactly
		// what would previously have doomed this batch to fail forever no
		// matter how many times it was retried.
		taps := humanTaps(600, time.Now().Add(-10*time.Minute), 30)
		if _, err := svc.SubmitTaps(ctx, userID, taps); err != nil {
			t.Fatalf("legitimate 20-minute backlog was rejected: %v", err)
		}
	})

	t.Run("several legitimate batches syncing close together after reconnect are not bulk-rejected", func(t *testing.T) {
		userID := newUser("+919999900003")
		// Reproduces the real incident: two honestly-paced batches, each
		// individually clean, whose own tap timestamps are far enough
		// apart (10 minutes vs. 5 minutes ago) that they were never
		// chanted within the same real 60-second window — but which
		// reach the server back-to-back, e.g. because a background
		// service reconnected and flushed a backlog then kept going.
		batch1 := humanTaps(116, time.Now().Add(-10*time.Minute), 40)
		if _, err := svc.SubmitTaps(ctx, userID, batch1); err != nil {
			t.Fatalf("first batch rejected: %v", err)
		}
		batch2 := humanTaps(100, time.Now().Add(-5*time.Minute), 40)
		if _, err := svc.SubmitTaps(ctx, userID, batch2); err != nil {
			t.Fatalf("second batch (landing right after the first) was wrongly rejected: %v", err)
		}
	})

	t.Run("taps genuinely chanted faster than the limit within the last minute are still caught", func(t *testing.T) {
		userID := newUser("+919999900004")
		// Two batches whose own timestamps really do fall inside the same
		// trailing 60-second window and together exceed the cap — this is
		// the actual pattern the limiter exists to catch (a fast sequence
		// split across requests to dodge the single-batch check), so it
		// must still be rejected.
		now := time.Now()
		batch1 := humanTaps(150, now.Add(-40*time.Second), 190)
		if _, err := svc.SubmitTaps(ctx, userID, batch1); err != nil {
			t.Fatalf("first fast batch unexpectedly rejected on its own: %v", err)
		}
		batch2 := humanTaps(150, now, 190)
		_, err := svc.SubmitTaps(ctx, userID, batch2)
		if !errors.Is(err, ErrBurstLimitExceeded) {
			t.Errorf("expected ErrBurstLimitExceeded for a genuine cross-batch burst, got %v", err)
		}
	})
}
