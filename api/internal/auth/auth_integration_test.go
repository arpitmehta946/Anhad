package auth

import (
	"context"
	"log/slog"
	"sync"
	"testing"

	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/store"
)

// codeCapture is a slog.Handler that remembers the last "code" attribute it
// saw — RequestOTP deliberately never returns the code (production sends it
// via SMS, never to the caller), so tests need to intercept it the same way
// a developer reads it off the console in local dev (docs/TECH_STACK.md §4).
type codeCapture struct {
	mu   sync.Mutex
	code string
}

func (c *codeCapture) Enabled(context.Context, slog.Level) bool { return true }

func (c *codeCapture) Handle(_ context.Context, r slog.Record) error {
	r.Attrs(func(a slog.Attr) bool {
		if a.Key == "code" {
			c.mu.Lock()
			c.code = a.Value.String()
			c.mu.Unlock()
		}
		return true
	})
	return nil
}

func (c *codeCapture) WithAttrs([]slog.Attr) slog.Handler { return c }
func (c *codeCapture) WithGroup(string) slog.Handler      { return c }

func (c *codeCapture) lastCode() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.code
}

func TestOTPAndTokenFlowIntegration(t *testing.T) {
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

	cleanupPhone := func(phone string) {
		t.Cleanup(func() {
			if _, err := st.PG.Exec(ctx, `DELETE FROM users WHERE phone_number = $1`, phone); err != nil {
				t.Errorf("cleanup user %s: %v", phone, err)
			}
			st.Redis.Del(ctx, "otp:cooldown:"+phone, "otp:code:"+phone, "otp:attempts:"+phone)
		})
	}

	newSvc := func() (*Service, *codeCapture) {
		capture := &codeCapture{}
		return NewService(st, slog.New(capture), cfg), capture
	}

	t.Run("the correct code succeeds and creates a new viewer", func(t *testing.T) {
		phone := "+919999900010"
		cleanupPhone(phone)
		svc, capture := newSvc()

		if err := svc.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("RequestOTP() error = %v", err)
		}
		code := capture.lastCode()
		if code == "" {
			t.Fatal("no code captured from RequestOTP's log line")
		}

		tokens, user, err := svc.VerifyOTP(ctx, phone, code)
		if err != nil {
			t.Fatalf("VerifyOTP() error = %v", err)
		}
		if tokens.AccessToken == "" || tokens.RefreshToken == "" {
			t.Error("VerifyOTP() returned an empty token")
		}
		if user.PhoneNumber != phone || user.Role != "viewer" {
			t.Errorf("user = %+v, want phone=%s role=viewer", user, phone)
		}
	})

	t.Run("a wrong code is rejected without consuming the real one", func(t *testing.T) {
		phone := "+919999900011"
		cleanupPhone(phone)
		svc, capture := newSvc()

		if err := svc.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("RequestOTP() error = %v", err)
		}
		realCode := capture.lastCode()

		if _, _, err := svc.VerifyOTP(ctx, phone, "000000"); err != ErrOTPInvalid {
			t.Errorf("VerifyOTP(wrong code) error = %v, want %v", err, ErrOTPInvalid)
		}
		// The real code must still work after one wrong attempt.
		if _, _, err := svc.VerifyOTP(ctx, phone, realCode); err != nil {
			t.Errorf("VerifyOTP(real code after one miss) error = %v, want nil", err)
		}
	})

	t.Run("otpMaxAttempts wrong guesses locks out the code entirely, including the real one", func(t *testing.T) {
		phone := "+919999900012"
		cleanupPhone(phone)
		svc, capture := newSvc()

		if err := svc.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("RequestOTP() error = %v", err)
		}
		realCode := capture.lastCode()

		var lastErr error
		for i := 0; i < otpMaxAttempts; i++ {
			_, _, lastErr = svc.VerifyOTP(ctx, phone, "000000")
		}
		if lastErr != ErrOTPMaxAttempts {
			t.Fatalf("after %d wrong attempts, error = %v, want %v", otpMaxAttempts, lastErr, ErrOTPMaxAttempts)
		}

		// The code is invalidated entirely at that point — even the real
		// one submitted right after must now fail, since brute-forcing
		// shouldn't get another shot at the same code.
		if _, _, err := svc.VerifyOTP(ctx, phone, realCode); err != ErrOTPInvalid {
			t.Errorf("VerifyOTP(real code after lockout) error = %v, want %v", err, ErrOTPInvalid)
		}
	})

	t.Run("an immediate second request is blocked by the cooldown", func(t *testing.T) {
		phone := "+919999900013"
		cleanupPhone(phone)
		svc, _ := newSvc()

		if err := svc.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("first RequestOTP() error = %v", err)
		}
		if err := svc.RequestOTP(ctx, phone); err != ErrOTPCooldown {
			t.Errorf("second immediate RequestOTP() error = %v, want %v", err, ErrOTPCooldown)
		}
	})

	t.Run("RefreshTokens rotates the pair and the used refresh token becomes single-use", func(t *testing.T) {
		phone := "+919999900014"
		cleanupPhone(phone)
		svc, capture := newSvc()

		if err := svc.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("RequestOTP() error = %v", err)
		}
		firstTokens, _, err := svc.VerifyOTP(ctx, phone, capture.lastCode())
		if err != nil {
			t.Fatalf("VerifyOTP() error = %v", err)
		}

		secondTokens, err := svc.RefreshTokens(ctx, firstTokens.RefreshToken)
		if err != nil {
			t.Fatalf("RefreshTokens() error = %v", err)
		}
		if secondTokens.RefreshToken == firstTokens.RefreshToken {
			t.Error("RefreshTokens() returned the same refresh token instead of rotating it")
		}

		// Reusing the now-spent first refresh token must fail — this is
		// the actual security property (a stolen-and-replayed token only
		// works once).
		if _, err := svc.RefreshTokens(ctx, firstTokens.RefreshToken); err != ErrRefreshInvalid {
			t.Errorf("RefreshTokens(already-used token) error = %v, want %v", err, ErrRefreshInvalid)
		}

		// The rotated token must still work.
		if _, err := svc.RefreshTokens(ctx, secondTokens.RefreshToken); err != nil {
			t.Errorf("RefreshTokens(the freshly-rotated token) error = %v, want nil", err)
		}
	})

	t.Run("an unknown refresh token is rejected", func(t *testing.T) {
		svc, _ := newSvc()
		if _, err := svc.RefreshTokens(ctx, "not-a-real-refresh-token"); err != ErrRefreshInvalid {
			t.Errorf("RefreshTokens(garbage) error = %v, want %v", err, ErrRefreshInvalid)
		}
	})

	t.Run("findOrCreateUser is idempotent across repeated logins", func(t *testing.T) {
		phone := "+919999900015"
		cleanupPhone(phone)
		svc, capture := newSvc()

		if err := svc.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("RequestOTP() error = %v", err)
		}
		_, firstUser, err := svc.VerifyOTP(ctx, phone, capture.lastCode())
		if err != nil {
			t.Fatalf("first VerifyOTP() error = %v", err)
		}

		if err := svc.RequestOTP(ctx, phone); err != nil {
			// Cooldown from the first request in this sub-test may still
			// be active — clear it directly rather than sleeping 30s.
			st.Redis.Del(ctx, "otp:cooldown:"+phone)
			if err := svc.RequestOTP(ctx, phone); err != nil {
				t.Fatalf("second RequestOTP() error = %v", err)
			}
		}
		_, secondUser, err := svc.VerifyOTP(ctx, phone, capture.lastCode())
		if err != nil {
			t.Fatalf("second VerifyOTP() error = %v", err)
		}

		if secondUser.ID != firstUser.ID {
			t.Errorf("second login created a new user (%s) instead of reusing the first (%s)",
				secondUser.ID, firstUser.ID)
		}
	})

	t.Run("the bootstrap admin phone gets admin role on its first signup only", func(t *testing.T) {
		phone := "+919999900016"
		cleanupPhone(phone)
		capture := &codeCapture{}
		svc := NewService(st, slog.New(capture), cfg)
		svc.bootstrapAdminPhone = phone

		if err := svc.RequestOTP(ctx, phone); err != nil {
			t.Fatalf("RequestOTP() error = %v", err)
		}
		_, user, err := svc.VerifyOTP(ctx, phone, capture.lastCode())
		if err != nil {
			t.Fatalf("VerifyOTP() error = %v", err)
		}
		if user.Role != "admin" {
			t.Errorf("user.Role = %q, want admin for the bootstrap phone's first signup", user.Role)
		}
	})
}
