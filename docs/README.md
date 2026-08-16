# Anhad *(working codename — see naming note below)*

**A sanctuary for bhajans, mantras & stutis.**

A short-form vertical video app restricted to one thing: devotional content — bhajans, mantras, stutis, chalisas, aartis, and spiritual discourse. No filmi songs, no political content, no algorithmic doomscrolling. Free to watch; creators pass a one-time verification step; original singers earn from an audio-reuse royalty pool; and a screen-off japa (chanting) counter with streaks gives the app a daily-practice habit loop mainstream social media doesn't have.

**Status:** Concept → Pre-MVP. These five documents are the planning foundation before any code is written.

---

## ⚠️ About the name

**"Anhad" is a placeholder, not a final decision.** Market research (see `PRD.md` §4.3) found that "Bhakti" and every obvious Bhakti-prefixed variant — BhaktiPath, myBhakti, Bhakti Sakha, Bhakti Game, BhaktiReel — are already in use by unrelated existing apps. Don't default to that word for the real brand. "Anhad" comes from *anhad naad*, the "unstruck sound" — a concept shared across Nada Yoga, Sant Kabir's poetry, and Sikh Gurbani. Do a proper trademark/domain search before committing to any name, including this one.

---

## What's in this repo

| Document | What it answers |
|---|---|
| **[`PRD.md`](./PRD.md)** | What are we building, for whom, and why? Includes market research, competitive landscape, personas, full feature list with priorities, content-moderation design, the finalized monetization model, and the open decisions still waiting on founder input. **Start here.** |
| **[`TECH_STACK.md`](./TECH_STACK.md)** | What do we build it with? Architecture diagram, mobile/backend/database/cache/CDN choices and the reasoning behind each, the AI moderation pipeline, and the cost/scaling path from day one to Instagram-scale. |
| **[`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md)** | In what order? A 5-phase build plan from foundation through public launch and post-launch scale, plus team roles, a QA checklist, and a launch checklist. |
| **[`FRONTEND_GUIDELINES.md`](./FRONTEND_GUIDELINES.md)** | What should it look and feel like? Color, type, the signature "Mala Ring" motif, motion principles, and an explicit list of mainstream-social-media patterns this product deliberately does not use. |
| **[`USER_FLOWS.md`](./USER_FLOWS.md)** | How does a new person actually move through the app? Research-grounded onboarding options for Viewers and Creators (competitor patterns from Duolingo, Calm, TikTok, Patreon), and why Admin should live outside the mobile app entirely. Not yet decided — options for discussion. |
| **[`GAPS.md`](./GAPS.md)** | What's still missing? A living, growing backlog — roles & permissions, trust & safety, payments compliance, and more. Check this before assuming something is handled. |

---

## The one-paragraph pitch

Devotional content already has enormous, proven demand — a single YouTube devotional channel has more subscribers than most streaming services' original content divisions and one of the highest-viewed videos ever uploaded from India. The problem isn't supply, it's context: that content sits one autoplay away from a comedy skit or political outrage on every platform it currently lives on, and creators compete against dance trends in an algorithm that has no concept of "sacred." Anhad is the protected space — same content, different context — with a real creator economy attached so the artists making it can actually earn from it.

## Quick glossary

Custom terms used throughout these docs, so you don't have to cross-reference `PRD.md` §6 every time:

- **Pranam** — replaces "Like"
- **Satsang** — replaces "Comment"
- **Prasad** — replaces "Share"
- **Jugalbandi** — replaces "Remix/Duet"
- **Smaran** — replaces "Save/Bookmark"
- **Sevak** — replaces "Follow"
- **Seva Pass** — the paid subscription tier
- **Japa** — the chanting/counting practice the daily-use tracker is built around (target: 1 mala = 108 chants/day)
- **Diya tokens** — in-app digital gifting, restricted to verified original artists (see `PRD.md` §10.2 for why)

## Core feature snapshot

- Vertical reel feed, filterable by a fixed devotional-category list — no black-box ranking algorithm at launch
- 3-layer AI moderation pipeline to distinguish authentic bhajans from filmi songs with devotional lyrics
- Screen-off japa counter with anti-cheat tap-timing checks and streak tracking
- One-time creator verification stake (₹99) that converts to wallet credit, never a recurring toll
- Audio-reuse royalty pool for original artists, paid monthly, always capped at a share of actual revenue — never a fixed liability
- Seva Pass subscription for background/lock-screen playback and offline downloads

Full detail, priorities, and the reasoning behind every one of these is in `PRD.md` §7.

## Tech stack snapshot

Flutter mobile client · Go (or Node/Fastify) backend · PostgreSQL 16 + Redis 7 · Cloudflare Stream & R2 for media · self-hosted via Coolify on a Bangalore/Mumbai VPS to start, with a clear path to managed infrastructure at scale without a rewrite. Full reasoning in `TECH_STACK.md`.

## Next step

Read `PRD.md` in full, especially §12 (Open Decisions) — a few product-scope questions (tradition scope, final brand name, diaspora launch timing) need a founder call before Phase 0 of `IMPLEMENTATION_PLAN.md` starts.
