package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// signedToken builds a JWT the same shape issueTokens produces, but lets
// each test control exactly what's wrong with it (expired, wrong secret,
// wrong algorithm) without needing a live Postgres/Redis just to exercise
// ParseAccessToken's validation logic — the actual security-critical
// surface here.
func signedToken(t *testing.T, secret []byte, method jwt.SigningMethod, claims *Claims) string {
	t.Helper()
	token, err := jwt.NewWithClaims(method, claims).SignedString(secret)
	if err != nil {
		t.Fatalf("sign test token: %v", err)
	}
	return token
}

func baseClaims(subject string, issuedAt, expiresAt time.Time) *Claims {
	return &Claims{
		Phone: "+919812345678",
		Role:  "viewer",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
			IssuedAt:  jwt.NewNumericDate(issuedAt),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
		},
	}
}

func TestParseAccessToken(t *testing.T) {
	secret := []byte("test-secret-do-not-use-in-prod")
	svc := &Service{jwtSecret: secret}
	now := time.Now()

	t.Run("a validly signed, unexpired token round-trips its claims", func(t *testing.T) {
		claims := baseClaims("user-123", now, now.Add(15*time.Minute))
		token := signedToken(t, secret, jwt.SigningMethodHS256, claims)

		got, err := svc.ParseAccessToken(token)
		if err != nil {
			t.Fatalf("ParseAccessToken() error = %v, want nil", err)
		}
		if got.Subject != "user-123" || got.Phone != "+919812345678" || got.Role != "viewer" {
			t.Errorf("claims = %+v, want subject=user-123 phone=+919812345678 role=viewer", got)
		}
	})

	t.Run("an expired token is rejected", func(t *testing.T) {
		claims := baseClaims("user-123", now.Add(-time.Hour), now.Add(-time.Minute))
		token := signedToken(t, secret, jwt.SigningMethodHS256, claims)

		if _, err := svc.ParseAccessToken(token); err == nil {
			t.Error("ParseAccessToken() = nil error, want rejection of an expired token")
		}
	})

	t.Run("a token signed with a different secret is rejected", func(t *testing.T) {
		claims := baseClaims("user-123", now, now.Add(15*time.Minute))
		token := signedToken(t, []byte("a-completely-different-secret"), jwt.SigningMethodHS256, claims)

		if _, err := svc.ParseAccessToken(token); err == nil {
			t.Error("ParseAccessToken() = nil error, want rejection of a wrong-secret token")
		}
	})

	t.Run("a token signed with the none algorithm is rejected, not silently trusted", func(t *testing.T) {
		// The classic JWT vuln: an attacker crafts an "alg: none" token
		// with arbitrary claims and no valid signature at all.
		claims := baseClaims("user-123", now, now.Add(15*time.Minute))
		token := jwt.NewWithClaims(jwt.SigningMethodNone, claims)
		signed, err := token.SignedString(jwt.UnsafeAllowNoneSignatureType)
		if err != nil {
			t.Fatalf("sign none-alg test token: %v", err)
		}

		if _, err := svc.ParseAccessToken(signed); err == nil {
			t.Error("ParseAccessToken() = nil error, want rejection of an alg:none token")
		}
	})

	t.Run("a token signed with a different HMAC-family method is still validated against the same secret path", func(t *testing.T) {
		// Confirms the "unexpected signing method" guard only rejects
		// genuinely non-HMAC methods (e.g. RS256), not just any deviation
		// from HS256 specifically — HS384/HS512 are still *jwt.SigningMethodHMAC.
		claims := baseClaims("user-123", now, now.Add(15*time.Minute))
		token := signedToken(t, secret, jwt.SigningMethodHS512, claims)

		if _, err := svc.ParseAccessToken(token); err != nil {
			t.Errorf("ParseAccessToken() error = %v, want nil (HS512 is still HMAC)", err)
		}
	})

	t.Run("garbage input is rejected, not panicked on", func(t *testing.T) {
		if _, err := svc.ParseAccessToken("not.a.jwt"); err == nil {
			t.Error("ParseAccessToken() = nil error, want rejection of malformed input")
		}
	})
}

func TestHashToken(t *testing.T) {
	a := hashToken("some-refresh-token-value")
	b := hashToken("some-refresh-token-value")
	c := hashToken("a-different-refresh-token-value")

	if a != b {
		t.Error("hashToken() is not deterministic for the same input")
	}
	if a == c {
		t.Error("hashToken() produced the same hash for different inputs")
	}
	if len(a) != 64 { // sha256 -> 32 bytes -> 64 hex chars
		t.Errorf("hashToken() length = %d, want 64 (hex-encoded sha256)", len(a))
	}
}

func TestGenerateRandomToken(t *testing.T) {
	tok, err := generateRandomToken(32)
	if err != nil {
		t.Fatalf("generateRandomToken() error = %v", err)
	}
	if len(tok) != 64 { // 32 bytes -> 64 hex chars
		t.Errorf("generateRandomToken(32) length = %d, want 64", len(tok))
	}

	seen := map[string]bool{}
	for i := 0; i < 100; i++ {
		tok, err := generateRandomToken(32)
		if err != nil {
			t.Fatalf("generateRandomToken() error = %v", err)
		}
		if seen[tok] {
			t.Fatalf("generateRandomToken() produced a duplicate across 100 calls — %s", tok)
		}
		seen[tok] = true
	}
}

func TestHashOTPBindsCodeToPhoneNumber(t *testing.T) {
	sameCodeDifferentPhone := hashOTP("+919812345678", "123456")
	other := hashOTP("+919999999999", "123456")
	if sameCodeDifferentPhone == other {
		t.Error("hashOTP() ignores the phone number — a leaked hash for one number would replay against another")
	}

	sameNumberDifferentCode := hashOTP("+919812345678", "654321")
	if sameCodeDifferentPhone == sameNumberDifferentCode {
		t.Error("hashOTP() ignores the code")
	}
}

func TestGenerateOTPCode(t *testing.T) {
	code, err := generateOTPCode(otpCodeLength)
	if err != nil {
		t.Fatalf("generateOTPCode() error = %v", err)
	}
	if len(code) != otpCodeLength {
		t.Errorf("generateOTPCode() length = %d, want %d", len(code), otpCodeLength)
	}
	for _, r := range code {
		if r < '0' || r > '9' {
			t.Fatalf("generateOTPCode() = %q, contains a non-digit character", code)
		}
	}
}

func TestClaimsContext(t *testing.T) {
	if _, ok := ClaimsFromContext(t.Context()); ok {
		t.Error("ClaimsFromContext() found claims in a bare context, want none")
	}

	claims := &Claims{RegisteredClaims: jwt.RegisteredClaims{Subject: "user-123"}}
	ctx := ContextWithClaims(t.Context(), claims)
	got, ok := ClaimsFromContext(ctx)
	if !ok {
		t.Fatal("ClaimsFromContext() found nothing after ContextWithClaims set it")
	}
	if got.Subject != "user-123" {
		t.Errorf("ClaimsFromContext() = %+v, want Subject=user-123", got)
	}
}
