// Package japa implements the screen-off chant (japa) tap counter: batched
// tap ingestion with the PRD.md §7.4 anti-cheat checks, a Redis live
// counter for in-progress UI display, and a flush to japa_sessions rather
// than a database write per tap (docs/TECH_STACK.md §5).
package japa

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/anhad/api/internal/store"
)

// Sentinel errors so HTTP handlers can map them to the right status code
// without string-matching.
var (
	ErrEmptyBatch     = errors.New("taps batch must not be empty")
	ErrTapsNotOrdered = errors.New("tap timestamps must be strictly increasing")
	ErrUniformTiming  = errors.New("tap timing is suspiciously uniform")
	ErrRateExceeded   = errors.New("tap rate exceeds 200 taps per minute")

	// ErrBurstLimitExceeded is the cross-batch cousin of ErrRateExceeded —
	// kept as a distinct sentinel (rather than reusing ErrRateExceeded) so
	// logs and tests can tell "this batch's own recorded pace was too
	// fast" apart from "too much arrived in one submission burst," which
	// have very different causes and, before this fix, were easy to
	// conflate when debugging a rejection after the fact.
	ErrBurstLimitExceeded = errors.New("too many taps submitted in a short window")
)

const (
	// maxTapsPerMinute mirrors the PRD.md §7.4 anti-cheat threshold and the
	// same number docs/TECH_STACK.md §5 uses for the Redis rate-limit key.
	// 120 was an untested guess that rejected real fast-paced chanting (a
	// mala done in ~50s, ~130/min); 200 was picked against actual measured
	// usage instead.
	maxTapsPerMinute = 200

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
	// check above. Measured against each tap's own timestamp (see
	// checkRateLimitWindow), not request arrival time.
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
	store  *store.Store
	logger *slog.Logger
}

func NewService(st *store.Store, logger *slog.Logger) *Service {
	return &Service{store: st, logger: logger}
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
	// per-batch limit by splitting a genuinely fast sequence across several
	// requests. Keyed off each tap's own recorded timestamp, not when the
	// request happened to reach the server — a batch recorded well before
	// now (offline, a lapsed auth token, anything that delays a flush)
	// already proved its honest pace via checkRate/checkUniformity above,
	// and its old timestamps fall straight out of this window regardless
	// of when it's finally submitted. An earlier version of this gated on
	// "is the batch's last tap recent," which is exactly wrong: someone
	// who kept chanting right through a reconnect has a recent last tap on
	// what's still a legitimate backlog, and that version rejected it
	// outright rather than letting it through or even retrying — a rate
	// limit must throttle, never destroy, so a rejection here maps to 429
	// (api/internal/server/japa.go), which the client treats as transient
	// and retries rather than deleting the batch.
	limited, err := s.checkRateLimitWindow(ctx, userID, taps)
	if err != nil {
		return nil, fmt.Errorf("check rate limit window: %w", err)
	}
	if limited {
		return nil, ErrBurstLimitExceeded
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

	// Deliberately not folded into the insert's own transaction, and
	// deliberately not fatal to this request: the taps are already durably
	// recorded above, so failing the whole submission over a streak-update
	// hiccup would make the client retry and double-insert this same
	// batch. UpdateStreakForDate always re-sums the day's total from
	// source rather than trusting a running delta, so a missed update here
	// self-corrects the moment any later batch that day (or a backfill)
	// calls it again.
	if err := s.UpdateStreakForDate(ctx, userID, endedAt); err != nil {
		s.logger.Error("japa streak update failed", "user_id", userID, "error", err)
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
// docs/TECH_STACK.md §5: a per-user sorted set keyed by each tap's own
// timestamp, not by when the request happened to reach the server.
//
// An earlier version used a plain counter incremented by request arrival
// time, gated so only "recent-looking" batches were checked at all. That
// conflated two different things — how fast someone actually chanted vs.
// how their batches happened to be split and timed reaching the server —
// and got both wrong at once: a large legitimate backlog (offline for 20
// minutes, then reconnecting) looks exactly like a live burst by that
// measure, while several small honest batches landing close together after
// a reconnect could still cross the counter's threshold even though no
// single one of them was fast. Scoring by the taps' own timestamps fixes
// both: a tap chanted 15 minutes ago doesn't count toward "the last 60
// seconds" just because it's finally being submitted now, and taps that
// really were produced within the last 60 seconds are caught regardless of
// how many separate requests they arrived in.
func (s *Service) checkRateLimitWindow(ctx context.Context, userID string, taps []time.Time) (bool, error) {
	key := "ratelimit:taps:" + userID
	now := time.Now()
	cutoff := now.Add(-rateLimitWindow)

	members := make([]redis.Z, len(taps))
	for i, t := range taps {
		members[i] = redis.Z{
			Score:  float64(t.UnixMilli()),
			Member: fmt.Sprintf("%d-%d", t.UnixNano(), i),
		}
	}

	pipe := s.store.Redis.TxPipeline()
	pipe.ZAdd(ctx, key, members...)
	pipe.ZRemRangeByScore(ctx, key, "-inf", strconv.FormatInt(cutoff.UnixMilli(), 10))
	card := pipe.ZCard(ctx, key)
	pipe.Expire(ctx, key, rateLimitWindow)
	if _, err := pipe.Exec(ctx); err != nil {
		return false, err
	}
	return card.Val() > maxTapsPerMinute, nil
}
