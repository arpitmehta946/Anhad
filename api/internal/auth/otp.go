// Package auth implements phone-OTP authentication: requesting and
// verifying one-time codes, and issuing/validating the resulting JWT
// access and refresh tokens.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/store"
)

// Sentinel errors so HTTP handlers can map them to the right status code
// without string-matching.
var (
	ErrOTPCooldown    = errors.New("otp request cooldown active")
	ErrOTPInvalid     = errors.New("otp code invalid or expired")
	ErrOTPMaxAttempts = errors.New("too many otp verification attempts")
)

const (
	otpCodeLength      = 6
	otpMaxAttempts     = 5
	otpTTL             = 5 * time.Minute
	otpRequestCooldown = 30 * time.Second

	accessTokenTTL  = 15 * time.Minute
	refreshTokenTTL = 30 * 24 * time.Hour
)

// Service provides the phone-OTP auth flow and JWT issuance/validation. It
// holds the shared Postgres/Redis connections plus the JWT signing secret.
type Service struct {
	store               *store.Store
	logger              *slog.Logger
	jwtSecret           []byte
	bootstrapAdminPhone string
}

func NewService(st *store.Store, logger *slog.Logger, cfg *config.Config) *Service {
	return &Service{
		store:               st,
		logger:              logger,
		jwtSecret:           []byte(cfg.JWTSecret),
		bootstrapAdminPhone: cfg.BootstrapAdminPhone,
	}
}

// RequestOTP generates a one-time code for phoneNumber and "sends" it. For
// local dev there is no live SMS provider wired up yet (docs/TECH_STACK.md
// §4 — MSG91/Twilio come later), so the code is logged to the console
// instead. The code's hash is stored in Redis with a short TTL; a per-phone
// cooldown key prevents immediate re-requests ahead of the Cloudflare rate
// limiting that fronts this endpoint in production.
func (s *Service) RequestOTP(ctx context.Context, phoneNumber string) error {
	cooldownKey := "otp:cooldown:" + phoneNumber
	set, err := s.store.Redis.SetNX(ctx, cooldownKey, "1", otpRequestCooldown).Result()
	if err != nil {
		return fmt.Errorf("otp cooldown check: %w", err)
	}
	if !set {
		return ErrOTPCooldown
	}

	code, err := generateOTPCode(otpCodeLength)
	if err != nil {
		return fmt.Errorf("generate otp code: %w", err)
	}

	codeKey := "otp:code:" + phoneNumber
	attemptsKey := "otp:attempts:" + phoneNumber
	pipe := s.store.Redis.TxPipeline()
	pipe.Set(ctx, codeKey, hashOTP(phoneNumber, code), otpTTL)
	pipe.Del(ctx, attemptsKey)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("store otp code: %w", err)
	}

	// STUB SEND: replace with a real SMS provider call once one is set up.
	// Logging at Info so it's easy to find in local dev console output.
	s.logger.Info("stub sms send: otp code", "phone_number", phoneNumber, "code", code)

	return nil
}

// VerifyOTP checks code against the stored hash for phoneNumber. On success
// it finds-or-creates the user by phone number and issues a fresh token
// pair. Failed attempts are counted and the code is invalidated entirely
// after otpMaxAttempts to slow down brute-forcing a 6-digit code.
func (s *Service) VerifyOTP(ctx context.Context, phoneNumber, code string) (*TokenPair, *User, error) {
	codeKey := "otp:code:" + phoneNumber
	attemptsKey := "otp:attempts:" + phoneNumber

	storedHash, err := s.store.Redis.Get(ctx, codeKey).Result()
	if errors.Is(err, redis.Nil) {
		return nil, nil, ErrOTPInvalid
	}
	if err != nil {
		return nil, nil, fmt.Errorf("get otp code: %w", err)
	}

	if subtle.ConstantTimeCompare([]byte(hashOTP(phoneNumber, code)), []byte(storedHash)) != 1 {
		attempts, aerr := s.store.Redis.Incr(ctx, attemptsKey).Result()
		if aerr != nil {
			return nil, nil, fmt.Errorf("track otp attempt: %w", aerr)
		}
		s.store.Redis.Expire(ctx, attemptsKey, otpTTL)
		if attempts >= otpMaxAttempts {
			s.store.Redis.Del(ctx, codeKey, attemptsKey)
			return nil, nil, ErrOTPMaxAttempts
		}
		return nil, nil, ErrOTPInvalid
	}

	s.store.Redis.Del(ctx, codeKey, attemptsKey)

	user, err := s.findOrCreateUser(ctx, phoneNumber)
	if err != nil {
		return nil, nil, fmt.Errorf("find or create user: %w", err)
	}

	tokens, err := s.issueTokens(ctx, user)
	if err != nil {
		return nil, nil, fmt.Errorf("issue tokens: %w", err)
	}

	return tokens, user, nil
}

func generateOTPCode(length int) (string, error) {
	const digits = "0123456789"
	code := make([]byte, length)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(digits))))
		if err != nil {
			return "", err
		}
		code[i] = digits[n.Int64()]
	}
	return string(code), nil
}

// hashOTP binds the code to the phone number so a leaked hash for one
// number can't be replayed against another.
func hashOTP(phoneNumber, code string) string {
	sum := sha256.Sum256([]byte(phoneNumber + ":" + code))
	return hex.EncodeToString(sum[:])
}
