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

## Status

Phase 0: HTTP server, config loading, graceful shutdown, health check.
Phase 1 adds phone-OTP auth, the reel/upload endpoints, and pgx/redis clients
wired to the services started by the root `docker-compose.yml`.
