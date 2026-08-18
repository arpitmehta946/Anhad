package japa

import (
	"testing"
	"time"
)

func day(offset int) time.Time {
	return time.Date(2026, 8, 1+offset, 0, 0, 0, 0, time.UTC)
}

func TestNextStreak(t *testing.T) {
	cases := []struct {
		name        string
		current     int
		longest     int
		lastChanted *time.Time
		today       time.Time
		wantCurrent int
		wantLongest int
	}{
		{
			name:        "first ever qualifying day",
			current:     0,
			longest:     0,
			lastChanted: nil,
			today:       day(0),
			wantCurrent: 1,
			wantLongest: 1,
		},
		{
			name:        "consecutive day extends the streak",
			current:     5,
			longest:     5,
			lastChanted: timePtr(day(0)),
			today:       day(1),
			wantCurrent: 6,
			wantLongest: 6,
		},
		{
			name:        "extending past the prior longest raises it",
			current:     5,
			longest:     9,
			lastChanted: timePtr(day(0)),
			today:       day(1),
			wantCurrent: 6,
			wantLongest: 9,
		},
		{
			name:        "a one-day gap breaks the streak, longest survives",
			current:     20,
			longest:     20,
			lastChanted: timePtr(day(0)),
			today:       day(2), // day 1 was missed entirely
			wantCurrent: 1,
			wantLongest: 20,
		},
		{
			name:        "a large gap also just restarts at 1",
			current:     3,
			longest:     20,
			lastChanted: timePtr(day(0)),
			today:       day(10),
			wantCurrent: 1,
			wantLongest: 20,
		},
		{
			name:        "reaching day 21 exactly",
			current:     20,
			longest:     20,
			lastChanted: timePtr(day(0)),
			today:       day(1),
			wantCurrent: 21,
			wantLongest: 21,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotCurrent, gotLongest := nextStreak(tc.current, tc.longest, tc.lastChanted, tc.today)
			if gotCurrent != tc.wantCurrent {
				t.Errorf("current streak = %d, want %d", gotCurrent, tc.wantCurrent)
			}
			if gotLongest != tc.wantLongest {
				t.Errorf("longest streak = %d, want %d", gotLongest, tc.wantLongest)
			}
		})
	}
}

func TestDaysBetween(t *testing.T) {
	if got := daysBetween(day(0), day(1)); got != 1 {
		t.Errorf("daysBetween(day0, day1) = %d, want 1", got)
	}
	if got := daysBetween(day(0), day(0)); got != 0 {
		t.Errorf("daysBetween(day0, day0) = %d, want 0", got)
	}
	if got := daysBetween(day(0), day(5)); got != 5 {
		t.Errorf("daysBetween(day0, day5) = %d, want 5", got)
	}
	// Time-of-day must not affect the calendar-day gap.
	late := day(0).Add(23 * time.Hour)
	early := day(1).Add(1 * time.Hour)
	if got := daysBetween(late, early); got != 1 {
		t.Errorf("daysBetween(23:00 day0, 01:00 day1) = %d, want 1", got)
	}
}

func timePtr(t time.Time) *time.Time { return &t }
