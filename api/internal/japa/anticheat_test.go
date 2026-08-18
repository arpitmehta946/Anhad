package japa

import (
	"errors"
	"testing"
	"time"
)

func TestCheckRate(t *testing.T) {
	base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

	cases := []struct {
		name    string
		elapsed time.Duration
		count   int
		wantErr error
	}{
		{
			name:    "a realistic fast mala (108 taps in 50 seconds) passes",
			elapsed: 50 * time.Second,
			count:   108,
			wantErr: nil,
		},
		{
			name:    "exactly at the 200/min boundary passes (only strictly-over rejects)",
			elapsed: time.Minute,
			count:   201, // 200 intervals over 1 minute = exactly 200/min
			wantErr: nil,
		},
		{
			name:    "just over the boundary is rejected",
			elapsed: time.Minute,
			count:   202, // 201 intervals over 1 minute = 201/min
			wantErr: ErrRateExceeded,
		},
		{
			name:    "a short burst at an impossible rate is rejected",
			elapsed: 100 * time.Millisecond,
			count:   10,
			wantErr: ErrRateExceeded,
		},
		{
			name:    "zero elapsed time (identical timestamps) is rejected, not a divide-by-zero",
			elapsed: 0,
			count:   5,
			wantErr: ErrRateExceeded,
		},
		{
			name:    "negative elapsed (out-of-order timestamps) is rejected",
			elapsed: -time.Second,
			count:   5,
			wantErr: ErrRateExceeded,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			first := base
			last := base.Add(tc.elapsed)
			err := checkRate(first, last, tc.count)
			if !errors.Is(err, tc.wantErr) {
				t.Errorf("checkRate() = %v, want %v", err, tc.wantErr)
			}
		})
	}
}

// jitteredIntervals builds intervals around a mean with the given jitter
// fraction (0 = perfectly uniform, 1 = +/-100% swing), deterministic via a
// fixed alternating pattern rather than randomness so the test is stable.
func jitteredIntervals(n int, mean time.Duration, jitterFraction float64) []time.Duration {
	intervals := make([]time.Duration, n)
	for i := range intervals {
		// Alternate above/below the mean so the average pace is preserved
		// while still producing genuine spread for the stddev check.
		sign := 1.0
		if i%2 == 0 {
			sign = -1.0
		}
		frac := jitterFraction * float64(i%5) / 4.0 // varies the magnitude too
		intervals[i] = mean + time.Duration(sign*frac*float64(mean))
	}
	return intervals
}

func TestCheckUniformity(t *testing.T) {
	t.Run("perfectly uniform intervals are rejected as robotic", func(t *testing.T) {
		intervals := make([]time.Duration, 20)
		for i := range intervals {
			intervals[i] = 500 * time.Millisecond
		}
		if err := checkUniformity(intervals); !errors.Is(err, ErrUniformTiming) {
			t.Errorf("checkUniformity() = %v, want %v", err, ErrUniformTiming)
		}
	})

	t.Run("realistic human jitter passes", func(t *testing.T) {
		// PRD.md §7.4: real human taps vary ~350-800ms.
		intervals := []time.Duration{
			420 * time.Millisecond, 610 * time.Millisecond, 380 * time.Millisecond,
			720 * time.Millisecond, 450 * time.Millisecond, 550 * time.Millisecond,
			690 * time.Millisecond, 400 * time.Millisecond, 800 * time.Millisecond,
			360 * time.Millisecond,
		}
		if err := checkUniformity(intervals); err != nil {
			t.Errorf("checkUniformity() = %v, want nil (legitimate human variance)", err)
		}
	})

	t.Run("near-zero variance just under the floor is rejected", func(t *testing.T) {
		// Alternates 500ms +/- 5ms — far tighter than any real human, well
		// under the 30ms stddev floor.
		intervals := make([]time.Duration, 20)
		for i := range intervals {
			if i%2 == 0 {
				intervals[i] = 495 * time.Millisecond
			} else {
				intervals[i] = 505 * time.Millisecond
			}
		}
		if err := checkUniformity(intervals); !errors.Is(err, ErrUniformTiming) {
			t.Errorf("checkUniformity() = %v, want %v", err, ErrUniformTiming)
		}
	})

	t.Run("jitter generator sanity check clears the floor comfortably", func(t *testing.T) {
		intervals := jitteredIntervals(30, 500*time.Millisecond, 0.6)
		if err := checkUniformity(intervals); err != nil {
			t.Errorf("checkUniformity() = %v, want nil", err)
		}
	})
}

func TestSubmitTapsGuardsBeforeAnyStoreAccess(t *testing.T) {
	// ErrEmptyBatch and ErrTapsNotOrdered are both returned before
	// SubmitTaps ever touches s.store — a zero-value Service is enough to
	// prove that, without needing Postgres/Redis.
	svc := &Service{}
	ctx := t.Context()
	base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

	t.Run("empty batch", func(t *testing.T) {
		_, err := svc.SubmitTaps(ctx, "user-1", nil)
		if !errors.Is(err, ErrEmptyBatch) {
			t.Errorf("SubmitTaps() = %v, want %v", err, ErrEmptyBatch)
		}
	})

	t.Run("out-of-order taps", func(t *testing.T) {
		taps := []time.Time{base, base.Add(-time.Second)}
		_, err := svc.SubmitTaps(ctx, "user-1", taps)
		if !errors.Is(err, ErrTapsNotOrdered) {
			t.Errorf("SubmitTaps() = %v, want %v", err, ErrTapsNotOrdered)
		}
	})

	t.Run("duplicate (non-increasing) timestamps", func(t *testing.T) {
		taps := []time.Time{base, base}
		_, err := svc.SubmitTaps(ctx, "user-1", taps)
		if !errors.Is(err, ErrTapsNotOrdered) {
			t.Errorf("SubmitTaps() = %v, want %v", err, ErrTapsNotOrdered)
		}
	})

	t.Run("a batch failing checkRate never reaches store access", func(t *testing.T) {
		// 10 taps in 100ms is far beyond maxTapsPerMinute — if this reached
		// s.store (nil here) it would panic instead of returning an error.
		taps := make([]time.Time, 10)
		for i := range taps {
			taps[i] = base.Add(time.Duration(i) * 10 * time.Millisecond)
		}
		_, err := svc.SubmitTaps(ctx, "user-1", taps)
		if !errors.Is(err, ErrRateExceeded) {
			t.Errorf("SubmitTaps() = %v, want %v", err, ErrRateExceeded)
		}
	})

	t.Run("a batch failing checkUniformity never reaches store access", func(t *testing.T) {
		taps := make([]time.Time, 10)
		for i := range taps {
			taps[i] = base.Add(time.Duration(i) * 500 * time.Millisecond)
		}
		_, err := svc.SubmitTaps(ctx, "user-1", taps)
		if !errors.Is(err, ErrUniformTiming) {
			t.Errorf("SubmitTaps() = %v, want %v", err, ErrUniformTiming)
		}
	})
}
