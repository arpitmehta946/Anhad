package auth

import (
	"context"
	"time"
)

// User is the subset of the users table auth cares about.
type User struct {
	ID          string
	PhoneNumber string
	Role        string
	CreatedAt   time.Time
}

// findOrCreateUser looks up a user by phone number, creating one on first
// login. Phone-OTP is the only signup path — there is no separate
// registration step. New users default to role = 'viewer' (per
// db/migrations/000001_create_users.up.sql and
// db/migrations/000006_add_roles_and_permissions.up.sql), except for the
// one phone number named by BOOTSTRAP_ADMIN_PHONE, which is granted
// role = 'admin' at the moment it's created — the one-time mechanism
// docs/GAPS.md flags as otherwise having no answer, since nothing can
// grant admin before an admin already exists. The ON CONFLICT branch never
// touches role, so this only ever applies on that phone's first signup —
// it won't re-promote an admin who was later demoted.
func (s *Service) findOrCreateUser(ctx context.Context, phoneNumber string) (*User, error) {
	const query = `
		INSERT INTO users (phone_number, role)
		VALUES ($1, $2)
		ON CONFLICT (phone_number) DO UPDATE SET phone_number = EXCLUDED.phone_number
		RETURNING id, phone_number, role, created_at
	`

	role := "viewer"
	if s.bootstrapAdminPhone != "" && phoneNumber == s.bootstrapAdminPhone {
		role = "admin"
	}

	var u User
	err := s.store.PG.QueryRow(ctx, query, phoneNumber, role).Scan(&u.ID, &u.PhoneNumber, &u.Role, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// getUserByID re-fetches a user's current role/phone at refresh time rather
// than trusting the (possibly stale, e.g. role-changed-since) refresh
// token's associated ID alone.
func (s *Service) getUserByID(ctx context.Context, id string) (*User, error) {
	const query = `SELECT id, phone_number, role, created_at FROM users WHERE id = $1`

	var u User
	err := s.store.PG.QueryRow(ctx, query, id).Scan(&u.ID, &u.PhoneNumber, &u.Role, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}
