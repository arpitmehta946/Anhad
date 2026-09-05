# Open Gaps & Backlog

**Companion to:** all other docs — this is the punch list, not a design spec
**Version:** 0.9 — living document, expected to grow
**Date:** August 21, 2026

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

- [ ] 🟡 **Local Whisper transcription quality is weak on compressed/forwarded audio — needs real-upload data, not more tuning against the test set.** Running `cmd/moderationeval` against `testdata/` surfaced two distinct problems, not one: (1) whisper.cpp's `small` model frequently hallucinates on noisy/re-compressed audio — token-repetition loops (the same phrase or even garbage script characters repeated dozens of times) that a downstream classifier correctly reports as `uncertain`, which is safe (holds for human review) but means low-quality audio produces mostly unusable pipeline verdicts, not wrong ones; (2) switching to the `medium` model fixed the hallucination on some of those files but is ~5-12x slower per file on this dev machine's CPU *and* introduced a new failure mode — a hard crash (`exit status 1`) on 4 of the 10 files tested, worse than the bad-but-present output `small` gave for the same files. Net decision: stayed on `small`. The pipeline's actual job — never auto-approve filmi/commercial content, hold anything uncertain for a human — held up in both configurations; at launch volume every held reel gets human review anyway, so transcript polish has a low ceiling on real impact right now. `testdata/` is all WhatsApp-forwarded clips (re-compressed, often re-forwarded multiple times), which is a worse audio distribution than real creator uploads will likely be — revisit transcription quality (bigger model, `openai` backend, or a different local model) once there's a sample of actual production uploads to tune against, not this test set.
- [x] **Instrumental-only content — partially resolved.** The pipeline (`internal/moderation`) now handles the "no lyrics" case explicitly rather than leaving it undefined: an empty/near-empty transcript classifies as `uncertain` and the reel is held for human review, never silently approved or rejected. That's the "plus human review" half of this item's own proposed answer. The other half — mandatory creator tagging of which composition an instrumental actually is — isn't built; still worth deciding before `Meditation & Naad` opens at real volume, since "hold every instrumental for a human" doesn't scale forever.
- [ ] 🟡 **Account transfer when a minor performer turns 18.** Family Accounts (`PRD.md` §4.5) put the parent as legal holder. On the child's 18th birthday, who owns the followers, the earnings history, the audio library entries, and the trust score? Needs a defined migration, or a 17-year-old with a real audience hits a wall.
- [ ] 🟡 **Does a child *appearing in* a video count as processing the child's data under DPDPA, even when the parent holds the account?** The Family Account design assumes the parent is the data principal. The video itself is arguably the child's personal data, which would trigger Section 9 obligations regardless of who holds the login. **This one needs a lawyer, not a product decision** — flagged rather than assumed either way.
- [ ] 🟡 **Age self-declaration is trivially bypassed.** A 15-year-old can simply claim to be 18. India has high device-sharing rates, and ID-based age gating is widely acknowledged to be prone to large-scale circumvention. The Family Account is opt-in by an honest parent; it does not detect a dishonest signup. Needs a stated position on detection and remediation (convert to Family Account vs. suspend), since it will happen.
- [x] **`creator_type` enum dropped.** `PRD.md` §10.2 retired the curator role, so the `original | curator` field no longer distinguished anything; migration `000012` drops the column and its two constraints. Note the Roles section above still lists it as resolved-with-`creator_type` — that resolution is superseded.
- [ ] 🟢 **Sant Vani needs a working definition for moderators.** "Historical saint-poetry" is clear for Kabir and Meera, less clear for a 20th-century saint whose recordings are still in copyright (author's life + 60 years under India's Copyright Act). The §4.2.1 rights rule mostly covers this — you may only upload your *own* recording — but the guidance for the moderation queue should say so explicitly.

## Onboarding & first-run experience

- [ ] 🔴 **No onboarding flow designed at all yet** — see `USER_FLOWS.md`, the new companion doc, for options.
- [ ] 🔴 **No explainer for the renamed interactions.** A first-time user seeing "Pranam" with a folded-hands icon and no context is a real confusion risk — directly contradicts the "easy to use" goal.
- [ ] 🟡 Language/tradition preference capture — not yet decided whether this happens before or after first content view.

## Sankalp & daily practice

- [ ] 🟡 **No minimum daily target floor.** The daily target is entirely self-chosen and locked for the vow (`PRD.md` §10.3) — nothing stops someone setting it to 1 chant/day and earning the 41-day Seva Pass trial on effectively no practice. Needs a decision: a floor (e.g. can't set below some fraction of a mala), or accept it as the honest cost of "you set your own target" and let the trial's own cost (a free week, not real money) absorb the risk.
- [ ] 🟢 **A second, concurrent, non-japa sankalp is a deliberate future build, not an oversight.** Someone vowing a daily Hanuman Chalisa or stuti recitation alongside (or instead of) japa needs a genuinely different counting model — a Chalisa is one completion, not 108 taps, so the bead-ring mechanic doesn't apply. Flagged here so it isn't quietly assumed to be "the same feature, different content" when it's actually built.

## Trust & safety

- [x] **In-app reporting + `reports` table — resolved.** A report action on each reel (reason: not devotional, filmi/commercial track, financial solicitation, medical/miracle claim, hate speech, other — `PRD.md` §8.0.1), a `reports` table (`db/migrations/000008`), rate-limited per reporter (Redis, 20/hour) plus `UNIQUE(reporter_id, reel_id)` against the same reel being re-reported — the two together are the brake on sectarian brigading `PRD.md` §12 flags. A moderator queue (`GET /v1/moderation/reports`, gated on `is_moderator`/`role=admin`) can dismiss a report or remove the reel (`api/internal/moderation`).
- [ ] 🔴 **Anti-scam rules not implemented.** `PRD.md` §8.0.1 defines the rule (no donation requests, payment handles, or external links anywhere — videos, captions, bios, comments). Needs enforcement in the upload pipeline and comment filter, not just a guidelines line. This is where actual financial harm to users happens and it has no technical control today.
- [ ] 🔴 **No medical/miracle-claim detection.** "Chant this to cure your illness" — real harm, real legal exposure, common in the category. Needs to be part of the classifier prompt, not a separate system. (The report reason exists now so a human can flag it after the fact; there's still no automated detection at upload time.)
- [x] **Comment default flipped to "reflection only" — resolved.** `users.comments_mode` (`db/migrations/000010`) now defaults to `reflection_only`; a creator opts into `open`, not the reverse. No creator-facing settings screen to change it ships yet — the default flip is what this item was actually about. The one concrete, enforced difference between the two modes today (`internal/social.PostSatsang`): a shorter max comment length in `reflection_only` (280 vs 500 chars), nudging toward a brief reflection over an argument — real reply/thread moderation is P1+ scope, not faked here.
- [ ] 🟡 **Verification bar undefined.** `PRD.md` §8.5 sets the framing (identity not endorsement, institutional accounts preferred, public record only). Still needs the written threshold: allegation vs. FIR vs. charges vs. conviction.
- [ ] 🟡 **Exit process unwritten** (`PRD.md` §8.6) — what happens when a verified figure is credibly accused. Must exist before it's needed.
- [x] **Admin audit log — resolved.** `moderation_audit_log` (`db/migrations/000008`) records moderator id, reel, report, action (`reel_removed`/`report_dismissed`), an optional reason, and a timestamp on every queue action — surfaced read-only at `GET /v1/moderation/audit-log` and in-app (moderation queue's history icon).
- [ ] 🟡 **Dev-DB test account has `is_moderator = true` — must not carry into production.** `+919812345678` was flagged a moderator directly in the local Postgres to verify the reporting/queue/audit-log flow end to end. That flag only exists in this machine's dev database (it's not in any migration or seed script), but a fresh production deploy that's ever restored from a dev dump, or a shared staging DB, could carry it forward silently. Needs a pre-launch check (or a `WHERE role != 'admin'` sanity query against prod) that no non-designated account holds `is_moderator`/`role = admin` before real users arrive.
- [ ] 🟢 Appeals flow for a rejected upload or a strike — mentioned in `PRD.md` §7.8, not built.

## Search & discovery

- [ ] 🟡 **No search at all** — finding a specific bhajan, artist, or mantra by name isn't possible yet, only category browsing (`PRD.md` §7.1).
- [ ] 🟢 Creator discovery beyond the feed itself (a "find creators" surface) — Patreon's own postmortem on this exact gap is worth a skim before designing it: search-only discovery measurably suppresses support for smaller creators.

## Notifications

- [x] **Daily practice reminder — resolved and built.** Local, on-device notification (`flutter_local_notifications`), not push — the phone already knows the time and today's progress, so no server round-trip or delivery infra is needed for this one. Set when a sankalp is taken, fires only if that day's target isn't met, at most once a day, non-guilt copy (`FRONTEND_GUIDELINES.md` §8).
- [x] **Notification strategy — decided.** On-device practice reminders are local-only (resolved above) and stay that way — no server round-trip needed. Push (FCM/APNs) is reserved for platform-originated events a closed app can't otherwise know about: a Diya received, a reel clearing moderation, a followed creator's new upload. Not a backend gap blocking anything today — it's scoped, just not built, because none of those trigger events exist yet either (Diya gifting is P2 and unbuilt; reel-approval and follow-activity notifications aren't wired). Pick a provider and build the delivery path when the first real trigger event ships, not speculatively before one does.
- [ ] 🟢 Once push infra is built: what specifically triggers a push (new Satsang reply, a followed creator's upload) needs its own short spec, checked against the anti-pattern list in `FRONTEND_GUIDELINES.md` §8 before anything ships. Never a streak-at-risk trigger — that's exactly the guilt pattern the sankalp reframing exists to avoid.

## Content lifecycle

- [ ] 🟡 **Can a creator edit a caption or delete a reel after posting?** Not decided.
- [x] **Audio library (`PRD.md` §7.3) — reel-derived half built.** Every reel's audio is now reusable and attributed the moment it clears moderation (migration 000013 wires the reel/moderation flow into the `audio_library` table migration 000003 first scaffolded but nothing ever wrote to): a browsable, category-filterable library (`GET /v1/audio-tracks`) showing the original creator and reuse count, "use this sound" (`POST /v1/audio-tracks/{id}/use`) that starts a new reel from a track, and per-track play counting (`POST /v1/audio-tracks/{id}/plays`) for the future royalty batch job to divide the monthly pool by (`PRD.md` §10.4). A minor performer's track defaults out of the library, parent opt-in only (`reels.audio_library_enabled`, same shape as `jugalbandi_enabled`). Deliberately kept separate from Jugalbandi's own `jugalbandi_reuse_count`: a duet performer records their own new mic audio alongside the source's video and never reuses the original recording as their own soundtrack, so it isn't an audio-reuse event the royalty engine should count — "use this sound" is, since the new reel's soundtrack literally is the borrowed track.
- [ ] 🟡 **Orphaned-reference problem — partially resolved.** A reel a moderator takes down after the fact no longer orphans reels built from its audio: `RemoveReel` now hides the track (`is_public = false`) rather than deleting it, so existing reuse/play history and every reel that already used it stay intact. What's still undecided: there is no creator-initiated *delete* for a reel or its track at all yet (`PRD.md` §7's own "can a creator delete a reel" item above) — once one exists, the same question returns for a real DELETE, not just a moderation-driven hide.
- [ ] 🟢 **Seeded library and real audio extraction — the other two `PRD.md` §7.3 P0/P1 pieces, still unbuilt.** (1) The seeded library itself (Tanpura drones, temple bells, harmonium scales, Vedic chant loops creators can record over for instant approval, `PRD.md` §8.1) has no admin-curated-track upload path — `audio_library.source_reel_id` is nullable specifically so a future seeded track (no source reel) can share the same table, but nothing creates one today. (2) `internal/audio.LocalAudioSource` does no real demuxing — it just points a track at its source reel's own video file, matching `internal/reels.LocalVideoStorage`'s own honesty about not being real Cloudflare Stream. Real extraction (ffmpeg locally, or Cloudflare Stream's own audio track / R2 in production) needs building before a track is ever played as audio-only rather than "a video file that happens to work when you only listen to it." Waveform preview + deity/raga/tempo/mood metadata (`PRD.md` §7.3 P1) also isn't built — `audio_library.deity`/`raga`/`duration_seconds` already exist as columns (migration 000003) but nothing populates them yet.

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
- [ ] 🟡 **Arrival screen intermittently drops zero-duration synthetic taps — likely a gesture-arena race with its continuous ripple ticker — and surfaced a real missing-timeout bug along the way.** The onboarding "Begin" button (`onboarding_arrival_screen.dart`) failed to respond to `adb shell input tap` during an on-device walkthrough. Two specific hypotheses were ruled out by inspection: no `IgnorePointer` is missing (the button is a Column sibling *after* the animated ripple `Stack`, not inside it — they can't overlap — and Flutter's own `RenderStack.hitTestChildren` was checked against the SDK source and correctly clips hit-testing to match paint clipping), and there's no hit-area/drawn-position mismatch (a tap at the exact visually-computed center worked cleanly on a fresh launch). But the same tap, at the same coordinates, on unchanged code, then silently failed twice in a row — no navigation, no collapse animation, no exception in logcat — while logcat confirmed Android delivered a clean pointer-down/up to the app both times. That points at Flutter's gesture arena occasionally losing the race against this screen's continuously-running ticker-driven animation (the only screen in the app with a never-idle animation loop sitting one frame from an interactive button), not at touch delivery. Real touches work fine (confirmed manually); only zero-duration synthetic taps are affected, which makes this screen effectively untestable by adb-based automation. Pinning down the actual mechanism needs Flutter DevTools' gesture-arena tracing, not more adb probing. Separately, chasing this exposed a second, unrelated, genuinely-worth-fixing bug: none of the app's API clients (`reel_api_client.dart`, `audio_library_api_client.dart`, `profile_api_client.dart`, etc.) set a timeout on `http.get`/`http.post`, and Dart's `http` package has no default one — a dead/half-open socket (a stale `adb reverse` tunnel today; a real user's flaky mobile connection tomorrow) hangs the request indefinitely instead of surfacing the app's own already-correct "Couldn't load..." error state. Adding a sensible request timeout to every API client is a real fix, not a dev-environment workaround.
- [ ] 🟢 **App store release process** — staged rollout, versioning strategy — not thought through yet.

## Growth mechanics

- [ ] 🟢 **No referral/invite flow.** Not urgent pre-launch, but worth deciding before the Founding 50 cohort phase (`IMPLEMENTATION_PLAN.md` Phase 3), since word-of-mouth is explicitly the planned growth engine.
