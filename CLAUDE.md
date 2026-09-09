# CLAUDE.md

Guidance for Claude Code (and any future contributor) working in this repo.

## What this project is

**Anhad** *(working codename — not final, see naming note below)* is a
short-form vertical video app restricted to one content category: bhajans,
mantras, stutis, chalisas, aartis, and devotional discourse. No filmi songs,
no political content, no algorithmic doomscrolling. Viewers browse for free;
creators pass a one-time verification step; original singers earn from an
audio-reuse royalty pool instead of direct tipping; a screen-off japa
(chanting) counter with streaks gives it a daily-practice habit loop.

The core bet: devotional content already has enormous proven demand
(mainstream platforms prove that), but no platform protects the *experience*
— a bhajan playing next to a comedy skit or political outrage. Anhad's
product is the protection, not the content itself.

**"Anhad" is a placeholder brand name, not a decision** — "Bhakti" and every
obvious variant are already taken by competitors. Don't design anything
around this name being final.

## Where the real detail lives

This file is a summary, not the source of truth. Full detail is in `docs/`:

| Document | Read this for |
|---|---|
| [`docs/PRD.md`](docs/PRD.md) | Product scope, personas, feature priorities (P0/P1/P2), content moderation design, monetization model, open founder decisions. **Start here for "what" and "why."** |
| [`docs/TECH_STACK.md`](docs/TECH_STACK.md) | Architecture diagram and the reasoning behind every technology choice, from mobile client to deployment. **Read before adding a dependency or service.** |
| [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) | The phased build sequence (Phase 0 → 5), exit criteria per phase, team roles, QA/launch checklists. |
| [`docs/FRONTEND_GUIDELINES.md`](docs/FRONTEND_GUIDELINES.md) | Color tokens (Dusk/Prabhat themes), typography, the "Mala Ring" motif, motion, renamed interactions (Pranam/Satsang/Prasad/Jugalbandi/Smaran/Sevak), anti-patterns to never build. |
| [`docs/README.md`](docs/README.md) | One-paragraph pitch and glossary, if you just need the gist. |

When in doubt about a product decision, a naming choice, or a design token,
check `docs/` before improvising — most "obvious" defaults (pastel gradients,
red notification badges, generic heart icons, permanent streak rewards) are
explicitly called out there as things this product deliberately does not do.

## Repo layout

```
mobile/           Flutter client (Dart + Riverpod)
api/               Go backend API
docker-compose.yml Local Postgres 16 + Redis 7
docs/              Planning docs (see table above)
```

This is currently mid-**Phase 1** per `docs/IMPLEMENTATION_PLAN.md`. Phone-OTP
auth, the japa tap counter (screen-off capture, offline-first sync, streak
tracking with the §10.3 Seva Pass trial grant), reel upload, the feed,
moderation v0, and the seeded-audio-library mechanism (migration, storage,
`cmd/seedaudio`, "use this sound") are all built and exercised end-to-end.
What's left of Phase 1's exit criteria is content, not code: the seeded
library's manifest (`api/seed_audio/manifest.json`) lists the ~15–20 target
tracks, but the actual recordings haven't been sourced yet, so
`cmd/seedaudio` currently seeds nothing.

## Tech stack at a glance

- **Mobile:** Flutter + Riverpod, Isar (offline-first japa/streak queue),
  just_audio + audio_service (lock-screen playback), native MethodChannels
  for screen-off volume-key japa taps.
- **Backend:** Go, stdlib `net/http` with the Go 1.22+ routing enhancements.
  Phone-OTP auth, short-lived JWT + refresh rotation, once wired.
- **Data:** PostgreSQL 16 (source of truth, RLS-enforced) + Redis 7 (japa
  tap counters, rate limiting, trending audio, session revocation). PgBouncer
  sits in front of Postgres in production, not in local dev.
- **Edge/media (not yet wired locally):** Cloudflare Stream (video) + R2
  (audio/image storage, zero egress fees) + WAF.
- **Moderation pipeline (Phase 2):** Whisper STT → LLM devotional-intent
  classifier → ACRCloud audio fingerprint, async, never blocking upload.

Full reasoning for every choice is in `docs/TECH_STACK.md` — don't
reintroduce a debate (e.g. "why not Firebase," "why not S3") that's already
resolved there.

## Local development

```sh
cp .env.example .env
docker compose up -d          # Postgres 16 + Redis 7

cd api && cp .env.example .env && go run ./cmd/api   # http://localhost:8080/healthz

cd mobile && flutter pub get && flutter run
```

`mobile/ios/` (and the other untouched platform folders) is generated, not
checked in — see `mobile/README.md` for the one-time `flutter create` step.
`mobile/android/` **is** checked in as of the screen-off japa feature
(`docs/PRD.md` §7.4): it now contains real hand-written native code
(a foreground service, manifest permissions, platform-channel glue in
`MainActivity.kt`) that `flutter create` can't regenerate. Only its
generated/machine-local build output is gitignored.

## Working conventions

- This is a UGC platform legally subject to India's IT Rules 2021 from day
  one (`docs/PRD.md` §3.4, §9.3) — moderation, reporting, and grievance-flow
  work is compliance-critical, not optional polish.
- Never implement a permanent free-tier unlock for the japa streak reward —
  it must stay a 7-day trial (`docs/PRD.md` §10.3). Never gate spiritual
  progress (badges, streaks, leaderboard rank) behind payment — only
  convenience features (offline downloads, lock-screen playback) are ever
  paywalled.
- Royalty payouts are always a share of actual revenue, never a fixed
  per-play liability (`docs/PRD.md` §10.4).
- Follow the renamed-interaction vocabulary (Pranam/Satsang/Prasad/
  Jugalbandi/Smaran/Sevak) in UI copy, but keep screen-reader labels on the
  *functional* meaning (`docs/FRONTEND_GUIDELINES.md` §7) — the poetic name
  is a visual layer, not an accessibility substitute.
- Don't add red pulsing badges, infinite autoplay, streak-loss guilt
  language, or fake urgency on upsells — these are explicit anti-patterns
  (`docs/FRONTEND_GUIDELINES.md` §8).

## On-device automation (adb) safety rules

The dev phone is a real, shared device — the person testing alongside you
uses it for their own apps too, and it isn't always Anhad in the
foreground when a command runs. On 2026-09-09, a blind `adb shell input`
sequence landed in a WhatsApp conversation instead of Anhad and typed text
into a real, in-progress message to another person. It wasn't sent, but it
could have been. These rules exist because of that incident — follow them
for every adb-driven interaction with this phone, not just when things
seem to be going wrong:

- **Before any input, confirm Anhad is actually in the foreground.** Run
  `adb shell dumpsys window | grep mCurrentFocus` and check it names
  `com.anhad.anhad` before tapping or typing anything. If it doesn't, stop
  and tell the user rather than proceeding — don't assume a previous
  screenshot is still current.
- **Re-check foreground after anything that could hand off to another
  app** — the gallery/photo picker, a share sheet, a permission dialog, an
  incoming call or notification the OS brought to front. Never assume
  you're still looking at Anhad just because you were a moment ago.
- **Never type free text unless the user has explicitly asked for it in
  the current session.** Typing is what caused the incident — a stray tap
  is recoverable (nothing changes state), but characters typed into
  someone else's conversation are not something you can safely undo by
  guessing at more keystrokes.
- **Never tap send, submit, post, or confirm in any app other than
  Anhad.** If a flow requires leaving Anhad (e.g. a system share sheet or
  picker) and something needs to be actually submitted there, stop and
  ask rather than completing it yourself.
- **If you lose track of what's on screen, stop and screenshot before
  doing anything else.** Don't chain further taps on an assumption about
  current state — verify first.
