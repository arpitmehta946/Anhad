package server

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/anhad/api/internal/auth"
	"github.com/anhad/api/internal/config"
)

func TestPhoneNumberRegex(t *testing.T) {
	cases := []struct {
		phone string
		valid bool
	}{
		{"+919812345678", true},
		{"+12025550123", true},
		{"+911234567", true},          // 8 digits, the minimum allowed
		{"+123456789012345", true},    // 15 digits, the maximum allowed
		{"919812345678", false},       // missing the leading +
		{"+0919812345678", false},     // leading zero after the +
		{"+1234567", false},           // only 7 digits total, too short (< 8)
		{"+9198123456789012345", false}, // too long (16 digits)
		{"+91 9812345678", false},     // embedded space
		{"+91-9812345678", false},     // embedded dash
		{"", false},
		{"not-a-phone-number", false},
	}

	for _, tc := range cases {
		t.Run(tc.phone, func(t *testing.T) {
			got := phoneNumberRE.MatchString(tc.phone)
			if got != tc.valid {
				t.Errorf("phoneNumberRE.MatchString(%q) = %v, want %v", tc.phone, got, tc.valid)
			}
		})
	}
}

// signedTestToken builds a JWT independent of the auth package's own
// (unexported) issuance path, so this test exercises requireAuth's
// validation from the outside the same way a real client's token would
// arrive — not by reaching into auth's internals.
func signedTestToken(t *testing.T, secret string, claims *auth.Claims) string {
	t.Helper()
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(secret))
	if err != nil {
		t.Fatalf("sign test token: %v", err)
	}
	return token
}

func TestRequireAuth(t *testing.T) {
	const secret = "test-secret-for-server-auth-tests"
	// requireAuth only ever calls authSvc.ParseAccessToken, which never
	// touches the store — a nil *store.Store is safe here specifically
	// because these tests never exercise a store-backed path.
	authSvc := auth.NewService(nil, nil, &config.Config{JWTSecret: secret})

	var gotClaims *auth.Claims
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotClaims, _ = auth.ClaimsFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	})
	handler := requireAuth(authSvc)(inner)

	doRequest := func(authHeader string) *httptest.ResponseRecorder {
		gotClaims = nil
		req := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
		if authHeader != "" {
			req.Header.Set("Authorization", authHeader)
		}
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec
	}

	t.Run("no Authorization header is rejected", func(t *testing.T) {
		rec := doRequest("")
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("a header without the Bearer prefix is rejected", func(t *testing.T) {
		rec := doRequest("just-a-raw-token-no-prefix")
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("garbage after Bearer is rejected", func(t *testing.T) {
		rec := doRequest("Bearer not-a-real-jwt")
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("an expired token is rejected", func(t *testing.T) {
		now := time.Now()
		claims := &auth.Claims{
			Phone: "+919812345678",
			Role:  "viewer",
			RegisteredClaims: jwt.RegisteredClaims{
				Subject:   "user-1",
				IssuedAt:  jwt.NewNumericDate(now.Add(-time.Hour)),
				ExpiresAt: jwt.NewNumericDate(now.Add(-time.Minute)),
			},
		}
		rec := doRequest("Bearer " + signedTestToken(t, secret, claims))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("a token signed with the wrong secret is rejected", func(t *testing.T) {
		now := time.Now()
		claims := &auth.Claims{
			Phone: "+919812345678",
			Role:  "viewer",
			RegisteredClaims: jwt.RegisteredClaims{
				Subject:   "user-1",
				IssuedAt:  jwt.NewNumericDate(now),
				ExpiresAt: jwt.NewNumericDate(now.Add(15 * time.Minute)),
			},
		}
		rec := doRequest("Bearer " + signedTestToken(t, "a-completely-wrong-secret", claims))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", rec.Code)
		}
	})

	t.Run("a valid token is accepted and its claims reach the handler", func(t *testing.T) {
		now := time.Now()
		claims := &auth.Claims{
			Phone: "+919812345678",
			Role:  "verified_artist",
			RegisteredClaims: jwt.RegisteredClaims{
				Subject:   "user-42",
				IssuedAt:  jwt.NewNumericDate(now),
				ExpiresAt: jwt.NewNumericDate(now.Add(15 * time.Minute)),
			},
		}
		rec := doRequest("Bearer " + signedTestToken(t, secret, claims))
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, want 200", rec.Code)
		}
		if gotClaims == nil {
			t.Fatal("the wrapped handler never saw any claims in its context")
		}
		if gotClaims.Subject != "user-42" || gotClaims.Role != "verified_artist" {
			t.Errorf("claims = %+v, want Subject=user-42 Role=verified_artist", gotClaims)
		}
	})
}
