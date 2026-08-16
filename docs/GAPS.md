# Open Gaps & Backlog

**Companion to:** all other docs — this is the punch list, not a design spec
**Version:** 0.2 — living document, expected to grow
**Date:** August 16, 2026

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
- [ ] 🔴 **First-admin bootstrap problem — still genuinely open.** Nobody can grant `role = admin` before one exists. Needs a deliberate one-time mechanism (env-var allowlist checked on first signup, or a manual DB insert) before this schema goes live, or the founder account is locked out of its own moderation tools on day one.

## Onboarding & first-run experience

- [ ] 🔴 **No onboarding flow designed at all yet** — see `USER_FLOWS.md`, the new companion doc, for options.
- [ ] 🔴 **No explainer for the renamed interactions.** A first-time user seeing "Pranam" with a folded-hands icon and no context is a real confusion risk — directly contradicts the "easy to use" goal.
- [ ] 🟡 Language/tradition preference capture — not yet decided whether this happens before or after first content view.

## Trust & safety

- [ ] 🔴 **No in-app reporting mechanism, and no `reports` table.** Required by IT Rules 2021, not optional polish (`PRD.md` §3.4).
- [ ] 🟡 **No admin audit log** (who moderated/banned what, when, why) — same regulation, plus basic accountability once more than one moderator exists.
- [ ] 🟢 Appeals flow for a rejected upload or a strike — mentioned in `PRD.md` §7.8, not built.

## Search & discovery

- [ ] 🟡 **No search at all** — finding a specific bhajan, artist, or mantra by name isn't possible yet, only category browsing (`PRD.md` §7.1).
- [ ] 🟢 Creator discovery beyond the feed itself (a "find creators" surface) — Patreon's own postmortem on this exact gap is worth a skim before designing it: search-only discovery measurably suppresses support for smaller creators.

## Notifications

- [ ] 🔴 **Push notification infrastructure isn't chosen.** `TECH_STACK.md` never picked FCM/APNs or a delivery service — this is a real backend gap, not just a UI one.
- [ ] 🟡 What actually *triggers* a notification isn't defined (daily practice reminder, new Satsang reply, streak-at-risk) — needs its own short spec once the infra is picked, and needs to be checked against the anti-pattern list in `FRONTEND_GUIDELINES.md` §8 before anything ships.

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
- [ ] 🟢 **No automated test coverage** for the Flutter app yet — the Go API has been verified manually and thoroughly each step, but nothing's automated to keep it that way as it grows.
- [ ] 🟢 **App store release process** — staged rollout, versioning strategy — not thought through yet.

## Growth mechanics

- [ ] 🟢 **No referral/invite flow.** Not urgent pre-launch, but worth deciding before the Founding 50 cohort phase (`IMPLEMENTATION_PLAN.md` Phase 3), since word-of-mouth is explicitly the planned growth engine.
