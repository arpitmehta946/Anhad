// Package japa implements the screen-off chant (japa) tap counter: batched
// tap ingestion with the PRD.md §7.4 anti-cheat checks, a Redis live
// counter for in-progress UI display, and a flush to japa_sessions rather
// than a database write per tap (docs/TECH_STACK.md §5).
package japa

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/anhad/api/internal/store"
)

// Sentinel errors so HTTP handlers can map them to the right status code
// without string-matching.
var (
	ErrEmptyBatch     = errors.New("taps batch must not be empty")
	ErrTapsNotOrdered = errors.New("tap timestamps must be strictly increasing")
	ErrUniformTiming  = errors.New("tap timing is suspiciously uniform")
	ErrRateExceeded   = errors.New("tap rate exceeds 120 taps per minute")
)

const (
	// maxTapsPerMinute mirrors the PRD.md §7.4 anti-cheat threshold and the
	// same number docs/TECH_STACK.md §5 uses for the Redis rate-limit key.
	maxTapsPerMinute = 120

	// minTapsForAntiCheat is the smallest batch size that gives a
	// statistically meaningful sample for the rate/uniformity checks. A
	// short tail-end flush (session winding down) is accepted without
	// judgment rather than false-positived on too little data.
	minTapsForAntiCheat = 4

	// uniformStdDevFloor is the stddev-of-intervals floor below which tap
	// spacing reads as machine-generated. Real human taps vary ~350-800ms
	// per PRD.md §7.4; a scripted sequence firing at a fixed interval has
	// a stddev near zero.
	uniformStdDevFloor = 30 * time.Millisecond

	// liveCounterTTL bounds how long an abandoned live counter lingers in
	// Redis if a session is never flushed (app killed, connection lost).
	liveCounterTTL = 24 * time.Hour

	// rateLimitWindow is the rolling window for the cross-batch Redis rate
	// limit (docs/TECH_STACK.md §5), independent of the within-batch rate
	// check above.
	rateLimitWindow = 60 * time.Second
)

// Session is what a successful tap-batch flush wrote to japa_sessions.
type Session struct {
	ID        string
	TapCount  int
	StartedAt time.Time
	EndedAt   time.Time
}

// Service provides japa tap ingestion: anti-cheat evaluation, the Redis
// live counter, and flushing accepted batches to Postgres.
type Service struct {
	store *store.Store
}

func NewService(st *store.Store) *Service {
	return &Service{store: st}
}

// SubmitTaps validates a client-batched sequence of tap timestamps against
// the PRD.md §7.4 anti-cheat rules, then flushes it as a single row to
// japa_sessions — never one write per tap — and updates the live Redis
// counter used for in-progress UI display.
func (s *Service) SubmitTaps(ctx context.Context, userID string, taps []time.Time) (*Session, error) {
	if len(taps) == 0 {
		return nil, ErrEmptyBatch
	}

	intervals := make([]time.Duration, 0, len(taps)-1)
	for i := 1; i < len(taps); i++ {
		d := taps[i].Sub(taps[i-1])
		if d <= 0 {
			return nil, ErrTapsNotOrdered
		}
		intervals = append(intervals, d)
	}

	if len(taps) >= minTapsForAntiCheat {
		if err := checkRate(taps[0], taps[len(taps)-1], len(taps)); err != nil {
			return nil, err
		}
		if err := checkUniformity(intervals); err != nil {
			return nil, err
		}
	}

	// Cross-batch rolling window: catches a user staying under the
	// per-batch limit by splitting a fast sequence across several
	// requests. Batches that already failed the checks above never reach
	// here, so a rejected batch doesn't itself consume window budget.
	limited, err := s.checkRateLimitWindow(ctx, userID, len(taps))
	if err != nil {
		return nil, fmt.Errorf("check rate limit window: %w", err)
	}
	if limited {
		return nil, ErrRateExceeded
	}

	if err := s.incrLiveCounter(ctx, userID, len(taps)); err != nil {
		return nil, fmt.Errorf("increment live counter: %w", err)
	}

	startedAt := taps[0]
	endedAt := taps[len(taps)-1]

	const query = `
		INSERT INTO japa_sessions (user_id, tap_count, started_at, ended_at)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`
	var sessionID string
	if err := s.store.PG.QueryRow(ctx, query, userID, len(taps), startedAt, endedAt).Scan(&sessionID); err != nil {
		return nil, fmt.Errorf("insert japa session: %w", err)
	}

	// The batch is now durably recorded in Postgres — the live counter
	// only needs to reflect taps since the last flush.
	if err := s.resetLiveCounter(ctx, userID); err != nil {
		return nil, fmt.Errorf("reset live counter: %w", err)
	}

	return &Session{ID: sessionID, TapCount: len(taps), StartedAt: startedAt, EndedAt: endedAt}, nil
}

// checkRate rejects a batch whose average tap rate exceeds
// maxTapsPerMinute, per PRD.md §7.4.
func checkRate(first, last time.Time, count int) error {
	elapsed := last.Sub(first)
	if elapsed <= 0 {
		return ErrRateExceeded
	}
	tapsPerMinute := float64(count-1) / elapsed.Minutes()
	if tapsPerMinute > maxTapsPerMinute {
		return ErrRateExceeded
	}
	return nil
}

// checkUniformity rejects a batch whose inter-tap intervals are too evenly
// spaced to be a real human tapping, per PRD.md §7.4.
func checkUniformity(intervals []time.Duration) error {
	mean := meanDuration(intervals)

	var sumSq float64
	for _, d := range intervals {
		diff := float64(d - mean)
		sumSq += diff * diff
	}
	variance := sumSq / float64(len(intervals))
	stddev := time.Duration(math.Sqrt(variance))

	if stddev < uniformStdDevFloor {
		return ErrUniformTiming
	}
	return nil
}

func meanDuration(durations []time.Duration) time.Duration {
	var sum time.Duration
	for _, d := range durations {
		sum += d
	}
	return sum / time.Duration(len(durations))
}

// incrLiveCounter implements the live in-progress tap counter from
// docs/TECH_STACK.md §5: HINCRBY japa:live:<user_id> count <n>.
func (s *Service) incrLiveCounter(ctx context.Context, userID string, n int) error {
	key := "japa:live:" + userID
	pipe := s.store.Redis.TxPipeline()
	pipe.HIncrBy(ctx, key, "count", int64(n))
	pipe.Expire(ctx, key, liveCounterTTL)
	_, err := pipe.Exec(ctx)
	return err
}

func (s *Service) resetLiveCounter(ctx context.Context, userID string) error {
	return s.store.Redis.Del(ctx, "japa:live:"+userID).Err()
}

// checkRateLimitWindow implements the Redis-backed rolling rate limit from
// docs/TECH_STACK.md §5: INCR ratelimit:taps:<user_id> with a 60-second
// TTL, flagging a user who exceeds ~120 taps/minute across separate
// batches rather than just within a single one.
func (s *Service) checkRateLimitWindow(ctx context.Context, userID string, n int) (bool, error) {
	key := "ratelimit:taps:" + userID
	count, err := s.store.Redis.IncrBy(ctx, key, int64(n)).Result()
	if err != nil {
		return false, err
	}
	if count == int64(n) {
		// First increment of this window — start the TTL.
		if err := s.store.Redis.Expire(ctx, key, rateLimitWindow).Err(); err != nil {
			return false, err
		}
	}
	return count > maxTapsPerMinute, nil
}
