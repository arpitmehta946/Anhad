# Anhad API

Go backend for Anhad. See `../docs/TECH_STACK.md` §4-8 for the full architecture
and reasoning; this is the Phase 0 skeleton only (see `../docs/IMPLEMENTATION_PLAN.md`).

## Run locally

Requires Go 1.22+.

```sh
cp .env.example .env
go run ./cmd/api
```

Confirm it's up:

```sh
curl localhost:8080/healthz
```

## Database migrations

SQL migrations live in `../db/migrations` (plain `.up.sql`/`.down.sql` pairs,
applied via [golang-migrate](https://github.com/golang-migrate/migrate)).
With the `postgres` container from the root `docker-compose.yml` running:

```sh
go run ./cmd/migrate up          # apply all pending migrations
go run ./cmd/migrate down        # roll back one migration
go run ./cmd/migrate down 3      # roll back three migrations
go run ./cmd/migrate version     # print the current schema version
```

It reads `DATABASE_URL` the same way the API does (see `.env`). Applied
versions are tracked in the `schema_migrations` table.

## Status

Phase 0: HTTP server, config loading, graceful shutdown, health check, and
the initial schema (`users`, `user_subscriptions`, `japa_streaks`,
`japa_sessions`, `audio_library`, `reels`, `artist_wallets`,
`royalty_distributions` — see `docs/TECH_STACK.md` §6).
Phase 1 adds phone-OTP auth and the reel/upload endpoints on top of this.
