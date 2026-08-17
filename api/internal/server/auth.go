package server

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strings"

	"github.com/anhad/api/internal/auth"
)

// phoneNumberRE requires E.164 format (+ followed by 8-15 digits, first
// digit non-zero) — good enough to reject junk input before it ever hits
// the OTP flow or a real SMS provider.
var phoneNumberRE = regexp.MustCompile(`^\+[1-9]\d{7,14}$`)

func requestOTPHandler(logger *slog.Logger, authSvc *auth.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			PhoneNumber string `json:"phone_number"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if !phoneNumberRE.MatchString(req.PhoneNumber) {
			writeError(w, http.StatusBadRequest, "phone_number must be in E.164 format, e.g. +919812345678")
			return
		}

		err := authSvc.RequestOTP(r.Context(), req.PhoneNumber)
		switch {
		case err == nil:
			writeJSON(w, http.StatusAccepted, map[string]any{"message": "otp sent"})
		case errors.Is(err, auth.ErrOTPCooldown):
			writeError(w, http.StatusTooManyRequests, "otp already requested recently, try again shortly")
		default:
			logger.Error("otp request failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to request otp")
		}
	}
}

func verifyOTPHandler(logger *slog.Logger, authSvc *auth.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			PhoneNumber string `json:"phone_number"`
			Code        string `json:"code"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if !phoneNumberRE.MatchString(req.PhoneNumber) || req.Code == "" {
			writeError(w, http.StatusBadRequest, "phone_number and code are required")
			return
		}

		tokens, user, err := authSvc.VerifyOTP(r.Context(), req.PhoneNumber, req.Code)
		switch {
		case err == nil:
			writeJSON(w, http.StatusOK, map[string]any{
				"access_token":  tokens.AccessToken,
				"refresh_token": tokens.RefreshToken,
				"token_type":    "Bearer",
				"expires_in":    tokens.ExpiresIn,
				"user": map[string]any{
					"id":           user.ID,
					"phone_number": user.PhoneNumber,
					"role":         user.Role,
				},
			})
		case errors.Is(err, auth.ErrOTPInvalid):
			writeError(w, http.StatusUnauthorized, "invalid or expired code")
		case errors.Is(err, auth.ErrOTPMaxAttempts):
			writeError(w, http.StatusTooManyRequests, "too many attempts, request a new code")
		default:
			logger.Error("otp verify failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to verify otp")
		}
	}
}

func refreshTokenHandler(logger *slog.Logger, authSvc *auth.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			RefreshToken string `json:"refresh_token"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
			writeError(w, http.StatusBadRequest, "refresh_token is required")
			return
		}

		tokens, err := authSvc.RefreshTokens(r.Context(), req.RefreshToken)
		switch {
		case err == nil:
			writeJSON(w, http.StatusOK, map[string]any{
				"access_token":  tokens.AccessToken,
				"refresh_token": tokens.RefreshToken,
				"token_type":    "Bearer",
				"expires_in":    tokens.ExpiresIn,
			})
		case errors.Is(err, auth.ErrRefreshInvalid):
			writeError(w, http.StatusUnauthorized, "invalid or expired refresh token")
		default:
			logger.Error("token refresh failed", "error", err)
			writeError(w, http.StatusInternalServerError, "failed to refresh token")
		}
	}
}

// meHandler is a minimal authenticated route: it returns whatever the
// access token's claims say about the caller. It exists both as a real
// "whoami" endpoint and as the simplest possible check that requireAuth is
// actually gating access.
func meHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, ok := auth.ClaimsFromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"id":           claims.Subject,
			"phone_number": claims.Phone,
			"role":         claims.Role,
		})
	}
}

// requireAuth gates a handler behind a valid Bearer access token, injecting
// its claims into the request context for downstream handlers to read via
// auth.ClaimsFromContext.
func requireAuth(authSvc *auth.Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			const prefix = "Bearer "
			header := r.Header.Get("Authorization")
			if !strings.HasPrefix(header, prefix) {
				writeError(w, http.StatusUnauthorized, "missing bearer token")
				return
			}

			claims, err := authSvc.ParseAccessToken(strings.TrimPrefix(header, prefix))
			if err != nil {
				writeError(w, http.StatusUnauthorized, "invalid or expired token")
				return
			}

			next.ServeHTTP(w, r.WithContext(auth.ContextWithClaims(r.Context(), claims)))
		})
	}
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
