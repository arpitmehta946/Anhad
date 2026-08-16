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

// findOrCreateUser looks up a user by phone number, creating one (with the
// default 'seeker' role, per db/migrations/000001_create_users.up.sql) on
// first login. Phone-OTP is the only signup path — there is no separate
// registration step.
func (s *Service) findOrCreateUser(ctx context.Context, phoneNumber string) (*User, error) {
	const query = `
		INSERT INTO users (phone_number)
		VALUES ($1)
		ON CONFLICT (phone_number) DO UPDATE SET phone_number = EXCLUDED.phone_number
		RETURNING id, phone_number, role, created_at
	`

	var u User
	err := s.store.PG.QueryRow(ctx, query, phoneNumber).Scan(&u.ID, &u.PhoneNumber, &u.Role, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}
