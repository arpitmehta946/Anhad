# Tech Stack & Architecture

**Companion to:** `PRD.md`, `IMPLEMENTATION_PLAN.md`
**Version:** 0.1
**Date:** August 16, 2026

This document describes what to build with and why. It reflects the constraints that actually matter for this product: sub-second japa-tap response even with the screen off, near-zero marginal cost per audio play, a moderation pipeline that runs asynchronously without blocking uploads, and an infrastructure bill that stays low pre-revenue without requiring a rewrite later. Full schema DDL and Docker Compose files are implementation artifacts that belong in the repo itself (`/db/migrations`, `/infra`) once building starts — this document covers the architecture and the reasoning behind it.

---

## 1. Architecture at a Glance

```
┌───────────────────────────────────────────────────────────────────┐
│  MOBILE CLIENT — Flutter (Dart) + Riverpod                        │
│  • MethodChannels intercept volume keys for screen-off japa taps  │
│  • just_audio + audio_service for lock-screen background playback │
│  • Isar (local DB) queues taps/streaks offline, syncs when online │
└──────────────────────────────┬──────────────────────────────────────┘
                               │  HTTPS / HTTP-3, <10ms edge termination
                               ▼
┌───────────────────────────────────────────────────────────────────┐
│  EDGE — Cloudflare                                                 │
│  • WAF + DDoS mitigation + rate limiting                          │
│  • Cloudflare Stream — reel video, adaptive HLS, global CDN       │
│  • Cloudflare R2 — audio & image storage, zero egress fees        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │  <25ms
                               ▼
┌───────────────────────────────────────────────────────────────────┐
│  BACKEND API — Go (preferred) or Node.js + Fastify + TypeScript   │
│  • Phone-OTP auth, JWT (short-lived access + refresh rotation)    │
│  • REST (or gRPC internally), input validation, RLS-aware queries │
└─────────────────┬─────────────────────────────┬─────────────────────┘
                  │ <2ms                        │ <15ms (via PgBouncer)
                  ▼                             ▼
┌──────────────────────────┐   ┌──────────────────────────────────────┐
│  REDIS 7.x                │   │  POSTGRESQL 16+                       │
│  • Live japa tap counters │   │  • Users, wallets, streaks, reels,    │
│  • Rate-limit / anti-cheat│   │    royalty ledger — source of truth   │
│  • Trending audio (ZSET)  │   │  • Row-Level Security enforced        │
│  • Session/JWT revocation │   │  • Read replicas added as traffic     │
└──────────────────────────┘   │    grows (no code change required)    │
                                └──────────────────────────────────────┘
                  │
                  ▼ (async job queue)
┌───────────────────────────────────────────────────────────────────┐
│  BACKGROUND WORKERS — moderation & payouts, never block the UI    │
│  • Whisper STT → LLM devotional-intent classifier → ACRCloud check│
│  • RazorpayX/Cashfree payout webhooks; monthly royalty batch job  │
└───────────────────────────────────────────────────────────────────┘
```

---

## 2. Mobile Client

| Layer | Choice | Why |
|---|---|---|
| Framework | **Flutter (Dart)** | Single codebase for iOS + Android, compiles to native ARM, smooth 60fps vertical swipe (`PageView.builder`) — the standard choice for this exact app shape (Reels-style feeds). |
| State management | **Riverpod** | Predictable, testable, avoids the boilerplate of Bloc for a team this size. |
| Local persistence | **Isar**, via the **isar_community** fork (fallback: Hive) | Pure-Dart, very fast local NoSQL — stores queued japa taps and streak state so counting works fully offline and screen-off. The original `isar`/`isar_flutter_libs` packages are unmaintained (last release ~2023) and never added the Android `namespace` that AGP 8+ requires, so they fail to build on any current AGP. `isar_community` is a maintained fork with an identical v3 API that keeps up with AGP/Kotlin — drop-in, no code-level tradeoff. |
| Hardware interception | Native **MethodChannels** (Android/iOS) | Captures volume-button presses and manages wake-lock behavior for screen-off tap counting — this cannot be done in pure Dart. |
| Audio playback | **just_audio** + **audio_service** | The standard pairing for lock-screen/background audio playback on both platforms — required for the Seva Pass "screen locked, audio playing" feature. |
| Video playback | **video_player** / **better_player** with HLS | Adaptive-bitrate playback of Cloudflare Stream output. |

---

## 3. Edge, Media & CDN — Cloudflare

- **Cloudflare Stream** handles reel video: automatic transcoding into adaptive HLS/DASH, global edge delivery. This is the single biggest cost lever in the whole stack — never let raw video hit the origin server or the primary database.
- **Cloudflare R2** stores the audio library and images. R2's defining advantage here is **zero egress/bandwidth fees** — critical because the whole audio-reuse-royalty model depends on the *same* short audio file being played across potentially hundreds of thousands of different reels. On a provider that bills egress (e.g. raw AWS S3), that reuse pattern gets expensive fast; on R2 it's close to free.
- **Cloudflare WAF** sits in front of the API for DDoS mitigation, bot/scraper blocking, and rate limiting before traffic ever reaches the backend.
- Uploads never go directly from the client into the storage bucket — the backend issues short-lived, single-use **pre-signed upload URLs** (5-minute validity) per upload.

---

## 4. Backend API

**Primary recommendation: Go (Golang).** Goroutines give very high concurrency per server (handles large volumes of simultaneous requests, e.g. everyone's morning-chant session hitting the API around 6am) at a fraction of the memory footprint of a Node.js or Python process — this matters directly for keeping the pre-revenue infrastructure bill low.

**Acceptable alternative: Node.js + Fastify + TypeScript**, if the team is JS/TS-first. Fastify is meaningfully faster than Express and has built-in JSON-schema validation, which pairs well with strict API contracts.

Either way:
- **Auth:** phone-number OTP as the *only* login method (no passwords to hash, store, or leak) — via Firebase Auth/Twilio, or **MSG91** as an India-specific alternative that's typically cheaper per SMS for Indian numbers specifically, worth comparing at implementation time.
- **Tokens:** short-lived JWT access tokens (~15 min) + rotating refresh tokens, with revocation tracked in Redis so a compromised token can be killed immediately rather than waiting out its expiry.

---

## 5. Caching — Redis 7.x

Redis exists to keep the *hot path* (every japa tap, every feed load) off the relational database entirely:

- **Japa taps:** `HINCRBY japa:live:<user_id> count 1` — sub-millisecond, in-memory. The client batches and flushes to Postgres periodically (e.g. every 108 taps or after 30 seconds idle), not on every single tap.
- **Anti-cheat rate limiting:** a per-user Redis sorted set (`ratelimit:taps:<user_id>`) scored by each tap's own recorded timestamp, not by when the batch happened to reach the server; sessions exceeding ~200 taps/minute or showing unnaturally uniform tap timing get flagged. Scoring by the tap's own timestamp — rather than an earlier design that gated the check on "did this batch arrive recently" — means a delayed/backlog flush (client was offline, auth had lapsed, anything that holds up a sync) can never be bulk-rejected just for arriving in one burst on reconnect: its taps' timestamps fall outside the 60-second window regardless of when they're finally submitted, while a genuine live burst (taps whose own timestamps really do cluster within the last 60 seconds, however many requests they're split across) is still caught.
- **Trending audio:** Redis sorted sets (`ZINCRBY trending:audio 1 <audio_id>`) power the "use this sound" trending tab without a live database aggregation query.
- **Feed cache:** the top N reel IDs per category live in a sorted set; the API serves cached JSON rather than re-querying Postgres per request.

---

## 6. Database — PostgreSQL 16+

Standard, boring, open-source PostgreSQL — deliberately chosen over a proprietary or vendor-locked database so the data is portable (`pg_dump`/`pg_restore` works anywhere) as the platform grows.

**Core tables (conceptual — see `/db/migrations` in the actual repo for DDL):**

| Table group | Purpose |
|---|---|
| `users`, `user_subscriptions` | Profile, phone auth identity, role (Seeker / Verified Artist / Curator / Admin), Seva Pass subscription state |
| `japa_streaks`, `japa_sessions` | Current/longest streak, last-chanted date, per-session chant counts — written from the Redis batch flush, not per-tap |
| `audio_library` | Original tracks: artist, deity, raga, category, R2 URL, cumulative play/reuse counters |
| `reels` | Video metadata, linked `audio_id`, moderation state (`PENDING`/`APPROVED`/`REJECTED`), engagement counters |
| `artist_wallets`, `royalty_distributions` | UPI payout details, running balance, monthly royalty-pool calculation ledger |

**Connection handling:** all application connections go through **PgBouncer** (transaction pooling mode) rather than directly to Postgres — this multiplexes thousands of concurrent app-level connections into a small, stable pool of real database connections, which is what prevents a 6am traffic spike from exhausting Postgres's connection limit and crashing the app.

**Security:** Row-Level Security (RLS) policies enforced at the database level so that even a compromised or buggy client can never read or write another user's wallet, streak, or private data — this is a database-layer guarantee, not something that depends on the API code being bug-free.

**Scaling path:** start with a single primary instance. As read traffic grows, attach read replicas for profile/feed/catalog queries while writes (posts, payments, signups) continue to the primary — this requires no application rewrite, only infrastructure changes.

---

## 7. AI & Moderation Pipeline (async, never blocks upload)

| Stage | Tool | Purpose |
|---|---|---|
| Speech-to-text | Whisper (API or self-hosted) | Transcribes/transliterates sung lyrics for downstream classification |
| Intent classification | An LLM via API (Claude or a comparably capable model) | Judges whether lyrical content is devotional (invocation, deity praise, scripture) vs. secular/romantic/filmi — a nuanced linguistic-and-cultural judgment call that a keyword list cannot reliably make |
| Audio fingerprint match | ACRCloud or AcoustID | Flags uploads whose background audio matches a known commercial/Bollywood track |
| Frame/visual scan | Vision moderation API (e.g. Google Cloud Video Intelligence, AWS Rekognition) | Screens for explicit content in the video frames themselves, independent of the audio |

Full pipeline detail and the "why three layers" reasoning is in `PRD.md` §8 — this section is the *implementation* view. The job queue for this pipeline runs on **Redis Streams** (or **Asynq** for Go / **BullMQ** for Node) so uploads publish instantly and get a "processing" state while moderation runs in the background.

---

## 8. Payments & Payouts

| Need | Tool |
|---|---|
| Subscription billing (Seva Pass, Creator Studio Pro), one-time creator stake | Razorpay (India) |
| Automated creator payouts (UPI/IMPS/NEFT), penny-drop bank verification | **RazorpayX** or **Cashfree Payouts** |
| Cross-border payouts (future diaspora expansion) | **Stripe Connect** |

Payout automation, thresholds, and the TDS/compliance caveat are covered in `PRD.md` §9.3 and §10.4 — this is deliberately not re-litigated here since it's a compliance question, not a technology one.

---

## 9. Analytics & Observability

Given the product's own "no data harvesting" positioning against mainstream platforms, prefer a **self-hostable or privacy-respecting analytics stack** (e.g. self-hosted PostHog, or Plausible for lightweight web analytics) over sending user behavior data to a third-party ad-tech-adjacent SDK (Google/Firebase Analytics). This is a positioning choice as much as a technical one — it should be defensible in the app's own privacy policy.

---

## 10. Deployment & Hosting

**Day 1 → ~50k users:** Self-hosted via **Coolify** (open-source, Heroku-like deployment dashboard) on a single VPS from **Hetzner or DigitalOcean, Bangalore/Mumbai region** — gives 15–30ms database latency for Indian users and avoids the cold-start/pause behavior of free-tier managed platforms (a specific, validated concern from the founder discussion this doc is based on: free-tier Supabase-style projects pause after inactivity, which breaks a mobile app's reliability). Coolify gives a management dashboard for Postgres, Redis, and the backend service without hand-rolling server configuration. Estimated cost: **$10–20/month.**

**Growth (~50k–500k users):** Move to a managed PostgreSQL cluster (e.g. DigitalOcean Managed Databases, Mumbai region) + managed Redis + Cloudflare Stream for video, still self-hosting the API layer. Estimated cost: **$150–300/month.**

**Scale (5M+ users, SSMI territory):** Distributed backend services, multi-region Postgres read replicas, horizontal sharding of high-write tables like `japa_sessions` by user-ID hash. By this stage the platform should be self-funding this infrastructure from Seva Pass revenue — see the unit-economics model in `IMPLEMENTATION_PLAN.md`.

**Why self-host instead of a full managed BaaS (Supabase/Firebase) long-term:** because pure open-source Postgres + Redis means zero vendor lock-in — `pg_dump` and standard Redis persistence work anywhere — while a managed *server* (not a managed *platform*) still removes the actual pain points (patching, backups, failover) that make self-hosting risky. This is the balance the founder conversation converged on, and it holds at every stage above.

---

## 11. Security Checklist

- TLS 1.3 in transit, AES-256 at rest.
- Phone-OTP passwordless auth; no password database to ever leak.
- JWT short-lived access + rotating refresh, with Redis-backed revocation.
- PostgreSQL Row-Level Security on every user-scoped table.
- Pre-signed, single-use, time-limited upload URLs — clients never write directly to storage.
- Cloudflare WAF + rate limiting in front of every public endpoint.
- Tap-timing anomaly detection to catch automated japa-counter cheating (see §5).
- Least-privilege database roles: the API's database user should not have superuser rights; migrations run under a separate, more privileged role.
