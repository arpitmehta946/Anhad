package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// TokenPair is what gets returned to the client after a successful OTP
// verification.
type TokenPair struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int64 // access token lifetime, in seconds
}

// Claims are the JWT access token's payload. Role travels in the token so
// downstream handlers can authorize without a database round trip; it's
// only as fresh as the token, which is fine given the short (15 min) TTL.
type Claims struct {
	Phone string `json:"phone"`
	Role  string `json:"role"`
	jwt.RegisteredClaims
}

// issueTokens signs a short-lived JWT access token and generates an opaque
// refresh token. The refresh token itself is never stored — only its hash,
// mapped to the user ID in Redis with a TTL — so revocation is a single
// Redis DEL and a stolen Redis dump doesn't hand out usable tokens
// (docs/TECH_STACK.md §5, §11).
func (s *Service) issueTokens(ctx context.Context, user *User) (*TokenPair, error) {
	now := time.Now()

	claims := &Claims{
		Phone: user.PhoneNumber,
		Role:  user.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   user.ID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(accessTokenTTL)),
		},
	}
	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(s.jwtSecret)
	if err != nil {
		return nil, fmt.Errorf("sign access token: %w", err)
	}

	refreshToken, err := generateRandomToken(32)
	if err != nil {
		return nil, fmt.Errorf("generate refresh token: %w", err)
	}
	refreshKey := "refresh:" + hashToken(refreshToken)
	if err := s.store.Redis.Set(ctx, refreshKey, user.ID, refreshTokenTTL).Err(); err != nil {
		return nil, fmt.Errorf("store refresh token: %w", err)
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int64(accessTokenTTL.Seconds()),
	}, nil
}

// ParseAccessToken validates signature and expiry and returns the claims.
// Used by the auth middleware to gate protected routes.
func (s *Service) ParseAccessToken(tokenString string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Method)
		}
		return s.jwtSecret, nil
	})
	if err != nil {
		return nil, err
	}
	if !token.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

func generateRandomToken(numBytes int) (string, error) {
	b := make([]byte, numBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// claimsContextKey is unexported so only this package can mint context
// values under it, avoiding collisions with other packages' context keys.
type claimsContextKey struct{}

func ContextWithClaims(ctx context.Context, claims *Claims) context.Context {
	return context.WithValue(ctx, claimsContextKey{}, claims)
}

func ClaimsFromContext(ctx context.Context) (*Claims, bool) {
	claims, ok := ctx.Value(claimsContextKey{}).(*Claims)
	return claims, ok
}
