# Open Gaps & Backlog

**Companion to:** all other docs — this is the punch list, not a design spec
**Version:** 0.5 — living document, expected to grow
**Date:** August 20, 2026

This file exists because a fast-moving build (which this has been) is exactly how real gaps get missed until they're expensive. Nothing here is designed in depth — that's what `PRD.md`, `TECH_STACK.md`, and `USER_FLOWS.md` are for. This is just: **what don't we have an answer for yet.** Add to it whenever something new comes up; check items off as they get a real decision, not just a mention.

Priority key: 🔴 blocks real users touching the app · 🟡 blocks a clean launch · 🟢 can genuinely wait

---

## Roles & permissions — ✅ resolved August 16, 2026

Earlier passes on this section disagreed with each other — one said "3 roles," an even earlier schema sketch had 4, and neither handled an account needing to be more than one thing at once (a Verified Artist who is *also* a trusted moderator, which `PRD.md` §8.4 explicitly says is the normal case, not an edge case). Settled here, final — role and permission are treated as separate questions, not one field trying to do both jobs:

```
role                  viewer | creator | admin      — base tier, mutually exclusive
status                active | pending | suspended | banned  — independent of role
creator_type          original | curator | null     — only set when role = creator
is_moderator          boolean, default false        — layers on top of any role
is_founding_creator   boolean, default false         — cosmetic/economic badge only
trust_score           int, default 100               — already decided
```

Rejected alternatives, and why: a single 6+ value enum (`viewer/creator/admin/moderator/curator/...`) can't express "Verified Artist who is also a Moderator" without duplicate values for every combination. Full role-based access control (a many-to-many roles table) is the textbook-scalable answer but is real complexity this project doesn't need yet for a handful of capabilities — booleans convert into a proper RBAC table later without much pain; the reverse isn't true. The Grievance Officer / Compliance Officer required by IT Rules 2021 is a legal designation (a named person published in the ToS), not a new role — that person also needs `role = admin` to act on complaints, but doesn't get a new enum value for it.

- [x] Role / status / permission-flag split — resolved above.
- [x] Moderator vs. full Admin — resolved via `is_moderator`, not a separate role.
- [x] Original artist vs. curator — resolved via `creator_type`, confirmed as a flag not a role.
- [x] **First-admin bootstrap — resolved.** `BOOTSTRAP_ADMIN_PHONE` env var: the one phone number it names gets `role = admin` at the moment it first signs up (`api/internal/auth/user.go`'s `findOrCreateUser`), a one-time mechanism since the `ON CONFLICT` branch never touches role on a later login. Empty by default, so it's a no-op until explicitly configured.

## Gaps created by the August 18 scope decisions

These surfaced *while writing up* the decisions in `PRD.md` §4.1–4.5 and §10.2 — none is a blocker, but each needs an answer before the feature it touches is built.

- [ ] 🔴 **Instrumental-only content has nothing for the classifier to read.** A flute or harmonium rendition of a bhajan with no vocals produces no lyrics, so the Whisper → LLM stage of the pipeline (`PRD.md` §8.1) has no input at all. Currently undefined behaviour. Likely answer: fingerprint check plus mandatory creator tagging of which composition it is, plus human review. Needs deciding before the `Meditation & Naad` category opens.
- [ ] 🟡 **Account transfer when a minor performer turns 18.** Family Accounts (`PRD.md` §4.5) put the parent as legal holder. On the child's 18th birthday, who owns the followers, the earnings history, the audio library entries, and the trust score? Needs a defined migration, or a 17-year-old with a real audience hits a wall.
- [ ] 🟡 **Does a child *appearing in* a video count as processing the child's data under DPDPA, even when the parent holds the account?** The Family Account design assumes the parent is the data principal. The video itself is arguably the child's personal data, which would trigger Section 9 obligations regardless of who holds the login. **This one needs a lawyer, not a product decision** — flagged rather than assumed either way.
- [ ] 🟡 **Age self-declaration is trivially bypassed.** A 15-year-old can simply claim to be 18. India has high device-sharing rates, and ID-based age gating is widely acknowledged to be prone to large-scale circumvention. The Family Account is opt-in by an honest parent; it does not detect a dishonest signup. Needs a stated position on detection and remediation (convert to Family Account vs. suspend), since it will happen.
- [ ] 🟢 **`creator_type` enum is now dead.** `PRD.md` §10.2 retires the curator role; the `original | curator` field no longer distinguishes anything and should be dropped in a migration. Note the Roles section above still lists it as resolved-with-`creator_type` — that resolution is superseded.
- [ ] 🟢 **Sant Vani needs a working definition for moderators.** "Historical saint-poetry" is clear for Kabir and Meera, less clear for a 20th-century saint whose recordings are still in copyright (author's life + 60 years under India's Copyright Act). The §4.2.1 rights rule mostly covers this — you may only upload your *own* recording — but the guidance for the moderation queue should say so explicitly.

## Onboarding & first-run experience

- [ ] 🔴 **No onboarding flow designed at all yet** — see `USER_FLOWS.md`, the new companion doc, for options.
- [ ] 🔴 **No explainer for the renamed interactions.** A first-time user seeing "Pranam" with a folded-hands icon and no context is a real confusion risk — directly contradicts the "easy to use" goal.
- [ ] 🟡 Language/tradition preference capture — not yet decided whether this happens before or after first content view.

## Sankalp & daily practice

- [ ] 🟡 **No minimum daily target floor.** The daily target is entirely self-chosen and locked for the vow (`PRD.md` §10.3) — nothing stops someone setting it to 1 chant/day and earning the 41-day Seva Pass trial on effectively no practice. Needs a decision: a floor (e.g. can't set below some fraction of a mala), or accept it as the honest cost of "you set your own target" and let the trial's own cost (a free week, not real money) absorb the risk.
- [ ] 🟢 **A second, concurrent, non-japa sankalp is a deliberate future build, not an oversight.** Someone vowing a daily Hanuman Chalisa or stuti recitation alongside (or instead of) japa needs a genuinely different counting model — a Chalisa is one completion, not 108 taps, so the bead-ring mechanic doesn't apply. Flagged here so it isn't quietly assumed to be "the same feature, different content" when it's actually built.

## Trust & safety

- [ ] 🔴 **No in-app reporting mechanism, and no `reports` table.** Required by IT Rules 2021, not optional polish (`PRD.md` §3.4). Still the highest-priority unbuilt safety item.
- [ ] 🔴 **Anti-scam rules not implemented.** `PRD.md` §8.0.1 defines the rule (no donation requests, payment handles, or external links anywhere — videos, captions, bios, comments). Needs enforcement in the upload pipeline and comment filter, not just a guidelines line. This is where actual financial harm to users happens and it has no technical control today.
- [ ] 🔴 **No medical/miracle-claim detection.** "Chant this to cure your illness" — real harm, real legal exposure, common in the category. Needs to be part of the classifier prompt, not a separate system.
- [ ] 🟡 **Comment default should flip to "reflection only"** (`PRD.md` §8.0.1). Currently creators opt in to restriction; it should be the reverse. Small change, large effect on where sectarian conflict lands.
- [ ] 🟡 **Verification bar undefined.** `PRD.md` §8.5 sets the framing (identity not endorsement, institutional accounts preferred, public record only). Still needs the written threshold: allegation vs. FIR vs. charges vs. conviction.
- [ ] 🟡 **Exit process unwritten** (`PRD.md` §8.6) — what happens when a verified figure is credibly accused. Must exist before it's needed.
- [ ] 🟡 **No admin audit log** (who moderated/banned what, when, why) — IT Rules requirement, plus basic accountability once more than one moderator exists.
- [ ] 🟢 Appeals flow for a rejected upload or a strike — mentioned in `PRD.md` §7.8, not built.

## Search & discovery

- [ ] 🟡 **No search at all** — finding a specific bhajan, artist, or mantra by name isn't possible yet, only category browsing (`PRD.md` §7.1).
- [ ] 🟢 Creator discovery beyond the feed itself (a "find creators" surface) — Patreon's own postmortem on this exact gap is worth a skim before designing it: search-only discovery measurably suppresses support for smaller creators.

## Notifications

- [x] **Daily practice reminder — resolved and built.** Local, on-device notification (`flutter_local_notifications`), not push — the phone already knows the time and today's progress, so no server round-trip or delivery infra is needed for this one. Set when a sankalp is taken, fires only if that day's target isn't met, at most once a day, non-guilt copy (`FRONTEND_GUIDELINES.md` §8).
- [ ] 🔴 **Push notification infrastructure (FCM/APNs) still isn't chosen — needed for platform-originated events, not practice reminders.** Diya received, a reel approved, a followed creator posted — anything that happens server-side and needs to reach a phone that isn't currently open. `TECH_STACK.md` never picked a provider or delivery service; real backend gap, not just a UI one.
- [ ] 🟡 What triggers a *push* notification specifically (new Satsang reply, a followed creator's upload) isn't defined — needs its own short spec once the infra above is picked, and needs to be checked against the anti-pattern list in `FRONTEND_GUIDELINES.md` §8 before anything ships. Never a streak-at-risk trigger — that's exactly the guilt pattern the sankalp reframing exists to avoid.

## Content lifecycle

- [ ] 🟡 **Can a creator edit a caption or delete a reel after posting?** Not decided.
- [ ] 🟡 **Orphaned-reference problem:** if an artist deletes an original audio track that dozens of other reels are using via "use this sound," what happens to those reels — and to the royalty history tied to that track? Needs a real answer before the audio-reuse royalty engine goes live, not after.

## Account & session management

- [ ] 🟢 **Social sign-in (Google / Apple) — deliberately not in V1.** Phone-OTP alone keeps the trust/anti-bot model simple (one phone number = one identity, directly tied to the strike/ban system in `PRD.md` §7.5) and, concretely, exempts the app from Apple App Store Guideline 4.8 (any third-party login requires also shipping Sign in with Apple as an equivalent option). Worth revisiting for diaspora reach where SMS delivery is less reliable — but adding Google later makes Apple Sign-In mandatory too, plus real account-linking complexity: does a Google sign-in sharing an email with an existing phone account merge, or silently create a duplicate with a reset trust score and streak? Needs a real answer before it ships, not after. Not blocking anything now.

- [ ] 🟡 **Account recovery** — lost/changed phone number, locked out. No plan yet.
- [ ] 🟡 **Multi-device / session list** — logging in on a new phone, "log out of all other devices." Not designed.
- [ ] 🟢 **Blocking/muting between users** — no mechanism for a viewer to block a creator or another commenter yet.
- [ ] 🟢 **Account deletion & data export** — a real user right under DPDPA, not just good practice. Needs a defined flow, not just a backend capability.

## Platform & payments compliance

- [ ] 🔴 **App Store / Play Store in-app purchase requirement — genuinely unresolved, and bigger than it looks.** Apple's App Review Guideline 3.1.1 still requires digital subscriptions and virtual goods (Seva Pass, Diya tokens) bought *inside* the iOS app to go through Apple's own In-App Purchase system — taking a 15–30% cut — for users outside the US/EU, which is most of your actual market. The recent Epic v. Apple ruling that allows linking to external checkout mostly applies to US storefronts; it doesn't help an India-first launch the way headlines about it might suggest. Google Play has a parallel requirement with its own, differently-shaped exceptions. **This directly affects your unit economics** (`PRD.md` §10) — a 15–30% platform tax stacks on top of your own royalty-pool math. One common mitigation: sell subscriptions via a mobile website (not the native in-app checkout) where Razorpay can be used freely, and have the app simply reflect subscription status — adds friction, but sidesteps the App Store cut. **This needs a real decision, ideally with someone who's shipped IAP compliance before, not an assumption either way** — before any payment UI gets built, not after.
- [ ] 🟡 Legal: trademark search, ToS, Privacy Policy, Grievance Officer appointment — flagged since Phase 0, still untouched (`IMPLEMENTATION_PLAN.md`).

## Localization & accessibility infrastructure

- [ ] 🟡 Content can be *tagged* by language/script, but there's no actual in-app language-switching UI yet.
- [ ] 🟢 Devanagari/regional-script rendering has only been checked in design guidance (`FRONTEND_GUIDELINES.md` §3), never in a real running build.

## Reliability & offline resilience

- [ ] 🟡 **Unknown how the app behaves on poor connectivity** — real for a chunk of your likely audience (older users, rural India). The japa counter is designed to work fully offline (`PRD.md` §7.4); the feed and everything else hasn't been thought through for a flaky-connection scenario.

## Engineering hygiene

- [ ] 🟡 **No CI pipeline** — nothing runs tests or builds automatically on push yet.
- [ ] 🟡 **No crash reporting** for the mobile app (separate from the privacy-respecting product analytics already chosen in `TECH_STACK.md` §9 — this is about catching bugs, not tracking behavior).
- [x] **Automated test coverage for the Flutter app — done for the highest-risk surface.** The japa sync path (`daily_total_store`, `tap_recorder`, `japa_sync_service`, `japa_session_controller`) has 40+ test cases covering the exact lost-update/desync bug classes found during manual testing. Not yet extended to auth, the feed, or other features as they're built.
- [ ] 🟢 **App store release process** — staged rollout, versioning strategy — not thought through yet.

## Growth mechanics

- [ ] 🟢 **No referral/invite flow.** Not urgent pre-launch, but worth deciding before the Founding 50 cohort phase (`IMPLEMENTATION_PLAN.md` Phase 3), since word-of-mouth is explicitly the planned growth engine.
