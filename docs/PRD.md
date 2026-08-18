# Product Requirements Document

**Product (working codename):** Anhad
**Tagline:** A sanctuary for bhajans, mantras & stutis.
**Version:** 0.1 (Concept → Pre-MVP)
**Date:** August 16, 2026
**Status:** Draft for founder review — see [Open Decisions](#12-open-decisions-needing-your-input) before build starts

> **On the name.** "Anhad" comes from *anhad naad* — the "unstruck sound," a concept shared across Nada Yoga, Sant Kabir's poetry, and Sikh Gurbani, describing the divine vibration heard within rather than produced by striking an instrument. It's used here as a working codename, not a final brand. Do **not** name the product "Bhakti" or any Bhakti-prefixed variant — see [§4.3](#43-naming-collision-warning).

---

## 1. Executive Summary

Anhad is a short-form vertical video platform restricted to one content category: **bhajans, mantras, stutis, chalisas, aartis, and devotional discourse.** No filmi songs, no political content, no general entertainment. Viewers browse for free; creators pass a one-time verification step; original singers earn from an audio-reuse royalty pool instead of direct tipping; and a screen-off japa (chanting) counter with streaks gives the app a daily-use habit loop that generic social media doesn't have.

The core bet: mainstream platforms already prove the *demand* for this content (a single YouTube devotional channel has more subscribers than most countries have people), but they don't protect the *experience* — a bhajan plays next to a prank video next to political outrage. Anhad's product is the protection, not the content itself.

This document defines what to build, for whom, and why — grounded in the research in [§3](#3-market-research-findings), not just the product conversation that preceded it.

---

## 2. Problem Statement

People who open Instagram or YouTube specifically to watch a bhajan or listen to a mantra are dropped into an algorithm optimized for *engagement*, not *devotion*. In practice that means:

- A morning aarti autoplays into a comedy skit or a political reel because both share upbeat music or a similar thumbnail pattern.
- Devotional creators compete in the same ranking system as dance trends and meme pages, so classically trained singers get buried under whatever is algorithmically "hot" that week.
- There's no reliable way to tell an authentic bhajan from a filmi song with devotional lyrics, or from AI-generated "faceless page" content — both circulate freely today (see [§3.1](#31-existing-supply-the-demand-is-already-proven)).
- Comment sections under devotional content regularly turn into unrelated arguments, which is jarring in a space meant for reflection.

None of this is a content-supply problem — devotional content is enormous and growing. It's a **context** problem: the same video that feels sacred on a temple screen feels cheapened sandwiched between ads and unrelated content.

---

## 3. Market Research Findings

### 3.1 Existing supply: the demand is already proven

- A single YouTube devotional channel (T-Series Bhakti Sagar) has **43 million subscribers** — the 33rd most-subscribed channel *globally* — and its top video has **1.9 billion views**, making it one of the highest-viewed Indian videos ever made.
- Devotional "status" and "reel" clips circulate constantly and organically across WhatsApp Status, Instagram Reels, and Snapchat, usually repackaged from the same handful of source videos by unofficial "faceless page" accounts — a real signal of demand, but also a preview of the **authenticity/AI-slop problem** Anhad's moderation has to solve (see [§8](#8-content-moderation--trust-requirements)).
- Elevation Capital, a major Indian VC, has publicly backed faith-and-devotion-content ventures (AppsForBharat/Trell), citing this same viewing behavior as an investment thesis — this is a fundable category, not a hobby idea.

### 3.2 Market sizing

| Market | Size | Growth |
|---|---|---|
| India spiritual wellness app market | ~$261M by 2033 | 15.6% CAGR (2025–2033) |
| Global spiritual wellness app market | ~$2.8–3.0B in 2026 → $5.5–9.9B by 2030–2035 (estimates vary by source) | ~14–17% CAGR |
| India's broader religious & spiritual market (temples, pilgrimage, products — not just apps) | $70.1B in 2025 → $135.4B by 2034 | 7.6% CAGR |
| India creator economy (all categories) | Influences $350B in consumer spending today, projected to exceed $1 trillion by 2030 (BCG, 2025) | — |
| India influencer marketing spend | Crossed ₹2,800 crore in 2024, projected to exceed ₹4,000 crore in 2026 | ~25% CAGR |

Two things matter more than the topline numbers: **paid in-app purchase is already the dominant monetization model** in spiritual wellness apps globally (~61–63% revenue share), which supports the Seva Pass subscription approach over an ads model — and the Indian government announced a **$1 billion creator economy fund** in 2025, signaling policy tailwind, not headwind, for this category.

### 3.3 Competitive landscape

No existing product combines *all four* of: (a) creator-uploaded short video, (b) devotional-only strict moderation, (c) a creator monetization/royalty economy, and (d) a japa/streak habit loop. But every individual piece is already validated by a real, sometimes crowded, competitor:

| Product | What it does | Gap vs. Anhad |
|---|---|---|
| **Sattva** (Art of Living / Sri Sri Ravi Shankar) | Premium curated Vedic meditations, chants, mantras, community challenges, trophies. Strong brand, real scale. | Top-down curated content library, not a creator-upload social platform. No original-artist economy. |
| **BhaktiPath (family of apps), myBhakti, Bhakti Sakha, Bhakti Game: Jap & Satsang** | Digital prayer books + **japa/mala counters + streaks** — several apps already do exactly this. | Personal practice tools, not social feeds. No video upload, no discovery, no creator income. This is the most important finding: **the japa-counter-with-streaks idea is not a differentiator by itself** — it's already commoditized. Anhad's differentiation has to be the social/creator layer on top of it. |
| **BhaktiReel** | Curated devotional content app (name alone is a collision risk — see [§4.3](#43-naming-collision-warning)). | Curated, not creator-upload as far as public listings show. |
| Bhakti-TV-style linear channels (SVBC, Bhakthi TV) + YouTube devotional mega-channels | Passive, high-reach broadcast viewing. | Zero interactivity, zero creator economy, zero personalization. |
| Instagram Reels / YouTube Shorts / WhatsApp Status (today's *de facto* platform) | Where devotional content already thrives at massive scale. | No protection from unrelated content, no devotional-specific creator economy, and — critically — this is where Anhad's own future creators are already building an audience. Cross-posting tools (already scoped in the product) matter for this reason. |
| Rgyan / "Bodhi" | AI-powered devotional *companion* (conversational guidance), launched 2025. | Different product shape entirely (chat-based guidance vs. social video), but confirms investor appetite for Indian devotional tech broadly. |

**The whitespace is the combination, not any single feature.** Anhad should not market itself primarily on "we have a japa counter" — market on the sanctuary/curation promise and the creator economy, and treat the japa counter as a retention *feature*, not the core pitch.

### 3.4 Regulatory reality (India)

Because Anhad is a user-generated-content platform operating in India, it is legally an "intermediary" under the **IT (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021**, regardless of size:

- **From day one:** must publish Terms of Service, Privacy Policy, and Community Guidelines; appoint a **Grievance Officer**; acknowledge complaints within 24 hours and resolve within 15 days; remove certain flagged content (impersonation, non-consensual intimate imagery) within 24 hours of a valid complaint; comply with lawful takedown orders within 36 hours.
- **At 5 million registered users**, Anhad becomes a "Significant Social Media Intermediary" (SSMI), which additionally requires an India-resident Chief Compliance Officer, a Nodal Contact Person for law enforcement coordination, monthly compliance reports, proactive automated content-detection tooling, and a physical India address. This is a real trigger to plan for well before hitting the number, not after.

This is treated as a hard non-functional requirement in [§9.3](#93-compliance) — not optional polish.

---

## 4. Product Scope & Non-Negotiables

### 4.1 What Anhad is

A vertical-video social app where the **only** permitted content categories are:

`Bhajan` · `Mantra` · `Stuti / Chalisa` · `Aarti` · `Kirtan / Sant Vani` · `Katha / Discourse` · `Meditation & Naad (sound healing)` · `Darshan & Sacred Spaces` (temple visits, nature, ritual footage — silent or backed by library audio)

### 4.2 What Anhad is explicitly not (V1)

- **Not** filmi songs, romantic/secular music, or commercial pop — even devotionally-themed remixes of commercial tracks are excluded (see the classification pipeline in [§8.1](#81-the-songs-vs-bhajans-problem)).
- **Not** a general "spirituality" or wellness catch-all (yoga tutorials, life-coaching, astrology, tarot). The V0 idea was broader; this scope is deliberately narrower because narrow is defensible and moderatable, broad is not.
- **Not** a space for political content, denominational attacks, or "aggressive debate" framed as discourse — see [§8.3](#83-the-gray-zone-policy) for where the line sits.
- **Not**, in V1, a marketplace or ad-sales platform — see [§10.5](#105-explicitly-out-of-scope-for-v1).

### 4.3 Naming collision warning

Search confirms **"Bhakti" is one of the most saturated words available for this product**: BhaktiPath (multiple unrelated apps use this exact name), myBhakti, Bhakti Sakha, Bhakti Game, Bhakti: Gita & Mantras, and BhaktiReel all already exist in app stores. Launching under any Bhakti-prefixed name creates real user-confusion and trademark risk. Treat brand naming as its own workstream with a proper trademark search — don't default to the obvious word.

### 4.4 Tradition scope — a decision to make consciously, not by default

The source conversation used heavily Hindu/Sanatan-coded terms (Sanskrit, Krishna, Shiva, puja) but also mentioned Gurbani and Sufi kalam. Trying to serve every dharmic and devotional tradition equally on day one multiplies moderation complexity (each tradition needs its own "what counts as authentic" classifier logic) and risks the app feeling unfocused to any one community.

**Recommendation:** launch V1 focused on Hindu/Sanatan devotional content (the largest addressable content base per [§3.1](#31-existing-supply-the-demand-is-already-proven)), with the data model, category tags, and moderation pipeline **architected from day one** to add Gurbani, Sufi qalam, Buddhist chant, and other traditions as clearly-scoped V2/V3 expansions rather than an afterthought retrofit. This is flagged as a founder decision in [§12](#12-open-decisions-needing-your-input), not decided unilaterally here.

---

## 5. Target Users

**Meera, 34 — the Seeker (viewer).** Urban professional, plays a bhajan or Hanuman Chalisa while getting ready in the morning. Currently uses YouTube/Instagram and is mildly annoyed every time the algorithm interrupts her routine with something unrelated. Won't pay to *join*, might pay ₹79/month for background play and offline downloads once she's used it daily for a few weeks. This persona also plausibly includes diaspora users (US/UK/Gulf) for whom the app is a connection to home.

**Radha, 27 — the Artist (verified creator).** Classically trained or self-taught bhajan singer, already posts on Instagram/YouTube and is frustrated that dance trends and comedy reels outrank her devotional content in the algorithm. Wants an audience that specifically came for *this*. Will tolerate a one-time verification fee if it visibly buys her real reach and a legitimate income path — she will not tolerate a recurring toll.

**Kavita, 40 — the Curator.** Doesn't sing, but is skilled at clipping satsang and pravachan footage (from public figures and gurus), adding Hindi/Sanskrit subtitles, and pairing scripture verses with ambient audio. Currently does this on Instagram. Copyright and attribution questions are real for this persona — see the resolved monetization model in [§10.2](#102-design-decision-who-gets-direct-monetization).

---

## 6. Renamed Core Interactions

Replacing generic social-media verbs is central to making Anhad feel distinct rather than a reskinned Instagram. This is the finalized naming convention (superseding earlier drafts in the founder conversation) — full visual/interaction treatment lives in `FRONTEND_GUIDELINES.md`.

| Standard action | Anhad name | Icon | Notes |
|---|---|---|---|
| Like | **Pranam** 🙏 | folded hands | Long-press reveals variant reactions: Shanti 🕊️ (peace), Gyaan 💡 (insight), Kripa ✨ (gratitude) |
| Comment | **Satsang** 💬 | — | Can be set to "reflection only" per creator to discourage debate |
| Share | **Prasad** 🍃 | — | "Distributing something blessed" |
| Remix / Duet | **Jugalbandi** 🪕 | — | For instrumental accompaniment or call-and-response chanting |
| Save / Bookmark | **Smaran** 📿 | mala bead | "To remember, for daily practice" |
| Follow | **Sevak** 🌸 | — | Joining a creator's circle |

---

## 7. Feature Requirements

Priority key: **P0** = required for MVP launch · **P1** = fast-follow within ~3 months of launch · **P2** = later / conditional on traction.

### 7.1 Content feed & discovery
- **P0** — Vertical, full-screen reel feed; reverse-chronological within a followed/category scope (no black-box ranking algorithm at launch — see [§9.1](#91-performance) on why simplicity is a feature here, not a limitation).
- **P0** — Mandatory category tag at upload time from the fixed list in [§4.1](#41-what-anhad-is); feed can be filtered by category.
- **P1** — "Mood/Vibe" switcher (Meditation & Breathwork / Chants & Sound Healing / Discourse / Daily Affirmations) as a saved filter preset, not a hidden setting.
- **P1** — Gentle session-end nudge ("You've spent 10 mindful minutes today") instead of infinite autoplay countdown.

### 7.2 Reflective interactions
- **P0** — Pranam, Satsang, Prasad, Smaran, Sevak per [§6](#6-renamed-core-interactions).
- **P0** — Creator-level "reflection only" comment mode.
- **P1** — Jugalbandi (remix/duet) recording flow.
- **P2** — Long-press reaction variants (Shanti/Gyaan/Kripa) on Pranam.

### 7.3 Spiritual audio & sound library
- **P0** — Seeded library (Tanpura drones, temple bells, harmonium scales, Vedic chant loops) creators can record over to get instant, frictionless approval (see [§8.1](#81-the-songs-vs-bhajans-problem)).
- **P0** — "Use this sound" flow identical in spirit to Reels/TikTok — tap an audio track from any reel to start a new one with it.
- **P1** — Waveform preview + metadata (deity, raga, tempo, mood) in the library browser.
- **P1** — Audio-reuse counter visible to the original artist ("used in 340 reels this month").

### 7.4 Japa / chant tracker
- **P0** — Screen-off-capable tap counter using hardware volume-key interception, so a phone can stay pocketed during chanting. Local-first (works offline), batched sync to the server.
- **P0** — Default target: 1 mala (108 chants)/day. Do **not** implement escalating daily targets (100 → 200 → 300) — see the rationale in the founder conversation this PRD is based on; escalating targets increase burnout and streak-breaking, which is the opposite of the intended habit loop.
- **P0** — Basic anti-cheat: reject sessions where inter-tap timing is suspiciously uniform (real human taps vary ~350–800ms) or where tap rate exceeds ~200/minute (a full mala done in well under a minute is still normal for fast chanting — measured against real usage, not a guess).
- **P1** — Streak tracking (current + longest), with a 21-day streak unlocking a **7-day** temporary Seva Pass trial (not a permanent unlock — see [§10.3](#103-the-streak-reward-must-be-temporary)).
- **P1** — "Sankalp Raksha" (streak repair) — a small paid option to restore a single missed day, ₹19.
- **P2** — Community/circle leaderboards ranked purely by verified chant count, never by payment status.

### 7.5 Creator onboarding & verification
- **P0** — Phone OTP signup for everyone; a separate "become a creator" flow gated by a one-time ₹99 verification stake.
- **P0** — Stake converts automatically to in-app wallet credit after 3 approved, guideline-passing posts — it is never charged again, and never refunded to a bank account (see the "why not a refund loop" reasoning already validated in the founder conversation — repeated pay/refund cycles lose money to payment-gateway fees and don't actually filter bad actors).
- **P0** — Trust score per creator; strikes for guideline violations; 3 strikes → account + phone number ban and stake forfeiture.
- **P1** — Verified Artist badge (visual identity in `FRONTEND_GUIDELINES.md`).

### 7.6 Wallet, payouts & monetization
See full detail in [§10](#10-monetization-model).
- **P1** — Artist wallet with UPI payout via RazorpayX/Cashfree, ₹500 minimum withdrawal threshold, PAN collection + penny-drop verification.
- **P1** — Seva Pass subscription (₹79/month or ₹499/year): background/lock-screen playback, offline downloads, lossless audio, ad-free.
- **P1** — Monthly audio-reuse royalty batch job (detail in [§10.4](#104-royalty-mechanics)).
- **P2** — Diya token gifting, restricted to verified original artists only (not curators) — see the design decision in [§10.2](#102-design-decision-who-gets-direct-monetization).
- **P2** — Creator Studio Pro (₹149/month): longer clip limits (up to 5 min for Katha/discourse), priority audio-library placement, detailed analytics.

### 7.7 Notifications
- **P0** — Minimal by default: no red pulsing badges, no "someone liked your post" spam. Notification copy and visual treatment specified in `FRONTEND_GUIDELINES.md`.
- **P1** — Optional daily practice reminder at a user-chosen time.

### 7.8 Trust, safety & admin tooling
- **P0** — Moderation queue UI for the community-moderator tier described in [§8.4](#84-community-led-moderation).
- **P0** — In-app reporting + appeal flow, required for IT Rules 2021 compliance regardless of user count.
- **P1** — Admin dashboard: content-classifier accuracy monitoring, strike/ban management, royalty-pool reconciliation view.

---

## 8. Content Moderation & Trust Requirements

### 8.1 The "songs vs. bhajans" problem

This is the single hardest and most important technical requirement, because Bollywood and devotional music genuinely share instrumentation (harmonium, dholak, tabla, flute), so audio timbre alone can't classify it. A three-layer pipeline, run asynchronously at upload (never blocking the uploader, but blocking *publication* to the public feed):

```
Upload
  │
  ▼
Layer 1 — Speech-to-text (Whisper or equivalent) → transliterate lyrics
  │
  ▼
Layer 2 — LLM contextual classifier: is the lyrical subject divine
          reverence / scripture / invocation, vs. romantic / party /
          filmi storytelling? (An LLM — e.g. Claude or a comparably
          capable model via API — is well suited to this specific
          judgment call; a keyword blocklist alone will not work.)
  │
  ▼
Layer 3 — Audio fingerprint match (ACRCloud / AcoustID) against
          commercial-music databases → auto-flag known filmi/pop tracks
  │
  ├── Passes all layers ──────────────► Published to feed
  └── Fails / uncertain ──────────────► Held; routed to community
                                        moderation queue (§8.4);
                                        creator notified with reason
                                        and an appeal path
```
Anything recorded over the **pre-approved library audio** ([§7.3](#73-spiritual-audio--sound-library)) can skip straight to publication, since the audio itself is already known-clean — this also gives creators a strong incentive to use the library, which lowers moderation load over time.

### 8.2 Category-tag verification

Every upload requires a category selection from the fixed list in [§4.1](#41-what-anhad-is) — this is a cheap, high-signal first filter and a required metadata field, not optional.

### 8.3 The gray-zone policy

Semi-devotional content (a classical ghazal, a Sufi kalam, a pop melody rewritten with Radha-Krishna lyrics, scripture discourse that veers into commentary on current events) needs a **written, example-driven policy**, reviewed by counsel, before launch — not resolved ad hoc by moderators. At minimum, define: interpretive scripture teaching is welcome; commentary that names real-world political parties, candidates, or attacks another faith is not, regardless of how it's framed as "discourse."

### 8.4 Community-led moderation

Trusted-tier accounts (verified artists, certified teachers, senior community moderators) review content flagged or held by the automated pipeline. This tier also doubles as the human backstop the IT Rules effectively require, and as a defense against classifier false positives/negatives — track both error rates as a KPI ([§11](#11-success-metrics--kpis)).

---

## 9. Non-Functional Requirements

### 9.1 Performance
API p95 latency target <100ms for feed/interaction endpoints; sub-2ms for japa tap acknowledgement (in-memory, not database-backed — see `TECH_STACK.md`). Full detail and the reasoning for the stack lives in `TECH_STACK.md`.

### 9.2 Security
Phone-OTP passwordless auth; JWT with short-lived access tokens + refresh rotation; row-level security so no user can read/write another user's wallet, streak, or session data even via a compromised client; TLS 1.3 in transit, AES-256 at rest.

### 9.3 Compliance
- India IT Rules 2021 obligations from day one (Grievance Officer, ToS/Privacy Policy/Community Guidelines published in-app, 24-hour complaint acknowledgment, 15-day resolution) — see [§3.4](#34-regulatory-reality-india).
- Plan the SSMI compliance package (Chief Compliance Officer, Nodal Contact Person, monthly reporting) well before 5 million registered users, not after.
- **Digital Personal Data Protection Act (DPDPA) considerations:** phone numbers, payment/PAN details, and voice recordings (from the japa/lyric-transcription pipeline) are all data requiring careful consent language and retention limits. Voice data in particular should be transcribed and discarded, not retained as raw audio, unless the user explicitly opts into a feature that needs it.
- **Tax withholding on creator payouts is genuinely unsettled and needs a CA, not this document.** India's TDS framework for platform-to-creator payments has recently been reorganized: the Income Tax Act, 2025 (effective April 1, 2026) consolidates provisions that used to sit under sections like 194-O (e-commerce/platform facilitation — historically 0.1%, with a ₹5 lakh/year exemption for individuals who've furnished PAN) and 194J (professional fees — 10% above ₹30,000/year) into a new unified framework under Section 393(1). Whether a royalty-pool payout to a singer counts as "platform-facilitated service income" or "professional fee income" affects the rate and threshold that applies. **Engage a CA to classify this correctly before the first payout goes out** — this is flagged, not resolved, deliberately.

---

## 10. Monetization Model

### 10.1 The three sustainable revenue streams (V1)

1. **Seva Pass subscription** (consumer, recurring) — ₹79/month or ₹499/year for background/lock-screen playback, offline downloads, lossless audio, no interstitials.
2. **One-time creator verification stake** — ₹99, anti-spam friction, converts to wallet credit after 3 clean posts (never a recurring charge — see [§7.5](#75-creator-onboarding--verification)).
3. **Platform cut on Diya token purchases** — 15% retained when a viewer sends a digital offering to a *verified original artist* (see [§10.2](#102-design-decision-who-gets-direct-monetization) for why this is restricted).

Creator payouts are never a fixed liability — see [§10.4](#104-royalty-mechanics). If the platform earns ₹0 in a month, it owes ₹0 in royalties that month. This single rule is what keeps the model solvent at any scale.

### 10.2 Design decision: who gets direct monetization

The founder conversation this PRD is based on correctly identified a problem and then, in later messages, drifted back toward a solution that reopens it — worth resolving explicitly here rather than carrying the contradiction forward:

- **The problem (correctly identified):** direct tipping/dakshina feels culturally awkward for sacred content, and a large share of accounts will be **curators**, not original artists — people clipping and subtitling a guru's public discourse. Paying personal dakshina to a curator/aggregator for someone else's words is ethically and possibly legally murky (attribution, consent, copyright).
- **The resolution used in this PRD:** Diya token gifting is available **only on content from Verified Original Artists** (singers, discourse-givers who are the actual source) — never on curated/clipped content. Curators instead earn through the pooled Community Seva Fund ([§10.3](#103-the-streak-reward-must-be-temporary)) based on watch time and engagement, which sidesteps the "who deserves this specific tip" problem entirely.

### 10.3 The streak reward must be temporary

Giving a **permanent** free Seva Pass for completing a 21-day chanting streak destroys the subscription funnel — once earned, that user has no further reason to ever pay. The reward must be a **7-day trial**, functioning as a zero-cost customer-acquisition mechanism: the user experiences background playback and offline audio, the trial expires, and they choose between resubscribing, doing another 21-day streak, or reverting to the free tier. All three outcomes are fine for the platform; a permanent giveaway is the only bad outcome.

Streak-based rewards should never gate *spiritual* progress (badges, milestones, leaderboard rank) behind payment — only *convenience* features (lock-screen playback, offline downloads, ambient pacing tracks) are ever paywalled. This preserves the "you cannot buy devotion" principle the founder conversation correctly insisted on.

### 10.4 Royalty mechanics

- Royalty pool = **30% of net platform revenue**, calculated and distributed monthly — never a fixed per-play rate, which is what would create unbounded liability.
- A "qualified play" = a view where the audio played for ≥5–7 seconds (filters out accidental swipes and bot clicks).
- Payout formula: `Artist's share = (Artist's qualified plays ÷ Total qualified plays platform-wide) × Monthly pool`
- Paid via RazorpayX or Cashfree to a UPI ID verified with a penny-drop check; ₹500 minimum withdrawal threshold to avoid gateway fees eating small payouts.

### 10.5 Explicitly out of scope for V1

Per direct founder instruction, **brand sponsorships and product affiliate commerce are deliberately excluded from V1** — not because they're bad ideas, but because they add commercial-relationship complexity (advertiser vetting, FTC/ASCI-equivalent disclosure rules) before the core product and moderation pipeline are proven. Revisit post-launch, not before.

---

## 11. Success Metrics / KPIs

Deliberately avoid optimizing for raw time-on-app — maximizing session length is the exact mainstream-platform pattern this product exists to reject. Prioritize consistency and completion over volume:

| Category | Metric |
|---|---|
| Activation | % of new users completing a japa session or watching 3+ reels in their first session |
| Retention | D1 / D7 / D30 retention; % of streak starters who reach day 21 |
| Engagement (intentionally *not* raw watch-time) | Session completion rate; Smaran (save) rate as a proxy for content resonance |
| Creator health | # verified creators; 30/90-day creator retention; median creator monthly earning; total royalty pool paid out |
| Monetization | Seva Pass conversion rate; MRR; ARPU; LTV:CAC |
| Trust & safety | Moderation queue turnaround time; classifier false-positive/false-negative rate on the bhajan-vs-song pipeline; appeal overturn rate |
| Platform health | Uptime %; API p95 latency; crash-free session rate |

---

## 12. Open Decisions Needing Your Input

These are called out rather than decided unilaterally:

1. **Tradition scope** ([§4.4](#44-tradition-scope--a-decision-to-make-consciously-not-by-default)): Hindu/Sanatan-first with a defined expansion path, or pan-dharmic from day one? Recommendation given, decision is yours.
2. **Final brand name** ([§4.3](#43-naming-collision-warning)): needs a proper trademark/domain search — "Anhad" is a placeholder, not a proposal to ship with.
3. **Diaspora/international launch sequencing**: India-first is assumed throughout this document (₹ pricing, UPI payouts, IT Rules compliance) — confirm whether US/UK/Gulf diaspora is a parallel launch market or a post-PMF expansion.
4. **Minimum age for creator accounts**: recommend 18+ for anyone receiving payouts (wallet/KYC implications), with viewing open to a general/family audience — confirm.

---

## Appendix: Research Sources Consulted

- Grand View Research — India & global spiritual wellness app market sizing
- Research and Markets, Towards Healthcare, Fundamental Business Insights — global spiritual wellness app market forecasts
- IMARC Group — India religious & spiritual market report
- Coherent Market Insights — India creator economy forecast; BCG "From Content to Commerce" (via WAVES 2025 coverage)
- PRS India, IAPP, ITIF, Mondaq, EFF, MeitY — IT Rules 2021 analysis
- TaxGuru, TaxBuddy, TaxGarden, XflowPay, Legal Service India — TDS / Income Tax Act 2025 analysis
- Elevation Capital — AppsForBharat investment perspective
- Google Play / App Store listings — BhaktiPath, myBhakti, Bhakti Sakha, Bhakti Game, BhaktiReel, Sattva, Bhajan — Devotional Songs App
