# Implementation Plan

**Companion to:** `PRD.md`, `TECH_STACK.md`
**Version:** 0.1
**Date:** August 16, 2026

This plan sequences the work so the platform never launches with an empty feed, never promises a payout it can't cover, and never builds a compliance obligation after it's already required — all three are answers to failure modes the founder conversation specifically worried about. Timeframes assume a small team (2–4 people); adjust proportionally.

---

## Phase 0 — Foundation (Weeks 1–2)

Nothing here is glamorous, but skipping it is how UGC platforms end up non-compliant or unbranded-in-a-corner later.

- [ ] Trademark/domain search and final brand name (do **not** default to a Bhakti-prefixed name — see `PRD.md` §4.3).
- [ ] Draft Terms of Service, Privacy Policy, and Community Guidelines (the gray-zone content policy in `PRD.md` §8.3 needs a lawyer's eyes here, not a moderator's judgment call later).
- [ ] Appoint/identify a Grievance Officer — required from day one under IT Rules 2021, not at scale.
- [ ] Register the business entity if not already done; open a business bank account for the payment-gateway relationship (Razorpay/RazorpayX onboarding needs this).
- [ ] Repo scaffolding: Flutter app skeleton, Go/Fastify API skeleton, Postgres + Redis via Docker Compose locally, Coolify set up on the target VPS.
- [ ] Finalize the design system from `FRONTEND_GUIDELINES.md` before any screen is built — retrofitting a design language after 10 screens exist is expensive.

**Exit criteria:** a developer can run the full stack locally, and the legal/compliance documents exist even in draft form.

---

## Phase 1 — Audio-First MVP Build (Weeks 3–8)

Deliberately audio/lightweight-video first, not a heavy 4K pipeline — this was a specific, correct call in the founder conversation, because bandwidth cost scales with video weight and there's no revenue yet to absorb it.

**Build:**
- Phone OTP auth + profile creation
- Reel upload → Cloudflare Stream, with mandatory category tagging (`PRD.md` §4.1)
- Vertical feed (reverse-chronological, filterable by category — no ranking algorithm yet)
- Renamed interactions: Pranam, Satsang, Prasad, Smaran, Sevak (`PRD.md` §6)
- Seeded audio library (target: 15–20 tracks) + "use this sound"
- Japa tap counter: screen-off capable, local-first, basic streak tracking, anti-cheat timing checks
- Moderation v0: automated audio-fingerprint check + **manual review queue** (the full Whisper→LLM→fingerprint pipeline lands in Phase 2 — don't block MVP on it; a human queue is an acceptable stopgap at low volume)

**Exit criteria:** a test user can sign up, post a reel with library audio, have it reviewed and published, and complete a japa session with a tracked streak.

---

## Phase 2 — Moderation & Monetization Backbone (Weeks 9–12)

- Full 3-layer automated moderation pipeline (Whisper STT → LLM classifier → ACRCloud fingerprint) as an async background job (`TECH_STACK.md` §7)
- Creator verification stake flow (Razorpay one-time payment, ₹99, auto-converts to wallet credit after 3 approved posts)
- Trust score + strike system
- Artist wallet + RazorpayX/Cashfree UPI payout integration, penny-drop verification
- Seva Pass subscription (Razorpay Subscriptions)
- Streak → 7-day reward pass automation (`PRD.md` §10.3)

**Exit criteria:** the full creator economy loop works end-to-end for a test artist — verify, post, get flagged/approved automatically, earn, withdraw.

---

## Phase 3 — Closed Beta / Founding Cohort (Weeks 13–16)

Solves the cold-start problem *before* any public marketing, per the seeding strategy validated in the founder conversation.

- **Recruit the "Founding 50"** — reach out directly to niche creators already active on Instagram/YouTube (classical music students, temple Kirtan singers, ashram youth vocalists) who already complain about algorithm burnout. Offer: founder badge, zero platform fees for life, pinned homepage discovery.
- **Seed the audio library properly** — record or license ~50 foundational tracks (tanpura scales, temple bells, Gayatri Mantra, Om soundscapes) so new creators can post within 30 seconds of signing up.
- **Seed 100–200 baseline posts** using public-domain devotional content so the app is never empty for a beta tester's first session.
- Internal QA pass: load testing (simulate a 6am traffic spike), security review, moderation-pipeline accuracy check against a labeled test set of known bhajans vs. known filmi songs.
- Iterate on the japa-tap anti-cheat thresholds and streak mechanics based on real usage, not assumptions.

**Exit criteria:** 50 active creators, a feed with enough content that a new user's first session doesn't feel empty, and a moderation false-positive/negative rate you're comfortable publishing to creators.

---

## Phase 4 — Public Launch (Week 17+)

- Time the public launch to a high-intent devotional calendar moment (Navratri, Shivratri, Janmashtami, or Diwali) rather than an arbitrary date — this is a real, low-cost distribution lever the founder conversation identified correctly.
- Open general creator registration with the verification stake live — by this point incoming creators see real engagement numbers and existing royalty payouts, which makes the ₹99 stake a non-issue rather than a barrier.
- Cross-posting tool live (watermark-free export formatted for sharing back to Instagram/YouTube with a link to the creator's Anhad profile) — this turns every creator's existing audience into acquisition for the new platform.
- Monitor the moderation queue closely in the first weeks; this is the highest-risk window for either a false-positive backlash from creators or a false-negative embarrassment (inappropriate content slipping through) — staff extra human review capacity for this window specifically.

**Exit criteria:** public app-store listing live, moderation holding, no P0 incidents in the first two weeks.

---

## Phase 5 — Post-Launch Growth (Month 5+)

- Audio-reuse royalty engine goes live as a real monthly payout (not just tracked) — `PRD.md` §10.4.
- Add read replicas and a managed Redis cluster once traffic patterns justify it (`TECH_STACK.md` §10) — not preemptively.
- Iterate on retention: Mood/Vibe feed switcher, Jugalbandi remix feature, Diya token gifting for verified artists.
- Begin the SSMI compliance package (Chief Compliance Officer, Nodal Contact Person, monthly reporting) with real lead time before crossing 5 million registered users (`PRD.md` §3.4) — this takes longer to set up correctly than it looks like it should.
- Revisit the explicitly-descoped items (brand sponsorships, affiliate commerce, tradition expansion beyond Hindu/Sanatan content) only once the core loop is proven.

---

## Team & Roles

Even a small team needs these functions covered — some can be one person wearing multiple hats early on, but the function shouldn't be *missing*:

| Role | Why it can't be skipped |
|---|---|
| Mobile (Flutter) developer | Owns the client, hardware interception, offline-first sync |
| Backend developer | Owns the API, moderation pipeline, payment integrations |
| Designer | Owns the design system in `FRONTEND_GUIDELINES.md` — a generic-looking devotional app undermines the "sanctuary" pitch immediately |
| Community / Trust & Safety lead | Runs the community moderation queue (`PRD.md` §8.4), handles the Grievance Officer function, is the human in the loop the IT Rules effectively require |
| Growth / creator relations | Runs the Founding 50 outreach (Phase 3), owns the launch-timing calendar strategy |

---

## Testing & QA Checklist (before every major release)

- [ ] Load test: simulate concurrent morning-chant traffic spike (japa taps + feed loads simultaneously)
- [ ] Moderation accuracy: run the classifier pipeline against a held-out labeled set of bhajans, filmi songs, and gray-zone content; track false-positive and false-negative rates over time
- [ ] Anti-cheat: verify the tap-timing detection actually rejects a scripted auto-tapper
- [ ] Payment: verify the creator stake → wallet-credit conversion, the royalty batch calculation, and a full withdrawal end-to-end in a sandbox environment
- [ ] Offline behavior: confirm japa sessions recorded fully offline (airplane mode) sync correctly once connectivity returns
- [ ] Accessibility: screen-reader labels on all icon-only actions (Pranam, Satsang, etc. — see `FRONTEND_GUIDELINES.md` §7)
- [ ] RLS check: attempt to read/write another test user's wallet and streak data directly via the API and confirm it's rejected

---

## Launch Checklist

- [ ] ToS, Privacy Policy, Community Guidelines published in-app and linked from app-store listings
- [ ] Grievance Officer contact published in-app per IT Rules 2021
- [ ] CA has signed off on the creator-payout TDS classification (`PRD.md` §9.3) before the first real payout goes out
- [ ] Founding 50 creators onboarded and actively posting
- [ ] Audio library seeded (≥50 tracks) and feed seeded (≥100 posts)
- [ ] Moderation queue staffed for the launch week specifically
- [ ] Cross-posting/export tool tested end-to-end
- [ ] Launch date confirmed against the devotional calendar, not just internal readiness
