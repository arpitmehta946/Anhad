# User Flows & Onboarding Options

**Companion to:** `PRD.md`, `FRONTEND_GUIDELINES.md`, `GAPS.md`
**Version:** 0.1 — options for discussion, not yet a final decision
**Date:** August 16, 2026

Nothing in this file is decided. It exists to turn "we need a user flow" into a small number of concrete, comparable options — grounded in how apps with the best first-session retention actually do it — so a real choice can be made instead of guessing. Once a direction is picked, the winning option should get folded into `PRD.md` §7 as the real spec; this file stops being load-bearing at that point.

## Why this matters more than it might seem

Industry benchmarks put median Day-1 app retention around **25%** — meaning roughly three out of every four people who install an app never open it a second time, and most of that loss happens in the very first session. The apps that beat this badly (Duolingo, Calm, Headspace, TikTok) share three patterns, not a hundred small tricks:

1. **A meaningful first action** — the user *does* the thing the app is for, in the first few minutes, not a tutorial about it.
2. **Progressive disclosure** — information and features are introduced exactly when they become relevant, never all at once upfront.
3. **An empty state that feels filled** — a new user should never be the first person in an obviously-empty room.

Point 3, encouragingly, is already solved on paper — `IMPLEMENTATION_PLAN.md` Phase 3 already plans to seed the audio library and post 100–200 baseline reels before any real launch. Points 1 and 2 are what the options below are actually about.

---

## Three roles need three different flows, not one

Worth stating plainly before anything else: "the app's user flow" isn't one thing. A Viewer opening the app for the first time, a Creator applying for verified status, and an Admin reviewing flagged content are three different jobs that shouldn't share a design.

**Recommendation on Admin specifically:** don't build it as mobile app screens at all. Instagram, TikTok, and YouTube all keep moderation and creator-management tooling on a separate web dashboard, not inside the consumer app — worth following that precedent here too. A lightweight internal web tool (the moderation queue and role/strike management already scoped in `PRD.md` §7.8) is faster to build, faster to iterate on, and doesn't force safety-critical tooling through mobile app-store review cycles every time it needs a change.

That leaves two flows that actually need real design work: **Viewer** and **Creator**.

---

## Viewer onboarding — three options

### Option A: Value first (TikTok / Instagram pattern)

Show the product before asking anything of the user. Research on this pattern is unusually specific: **deferred signup measurably lifts activation by 10–30%** across the apps studied.

```
[Open app] → [Real, curated feed plays immediately — sound on]
                          │
        [Small, dismissible interest-chip row: "Morning Aarti ·
         Hanuman Chalisa · Sound Healing · Sant Vani" — tap to
         lightly bias the feed, or ignore entirely]
                          │
   [First time they tap Pranam / Satsang / Smaran / Sevak]
                          │
        [One bottom sheet: quick explainer of that one term
                  + phone OTP, to save the action]
                          │
        [Everything else stays free to browse, forever,
                    with no account at all]
```
**Strength:** fastest possible path to "oh, this is nice" — no friction between install and value.
**Weakness:** the feed is generic on day one; no signal yet about what this specific person is drawn to.

### Option B: Personalize first (Calm / Headspace pattern)

A short, atmospheric quiz before any content, so the very first feed already feels chosen for this person.

```
[Single atmospheric opening screen — Dusk theme, one soft
 temple-bell sound, minimal text: "A quiet space for
 bhajans, mantras & stutis."]
                          │
    [3–4 questions: tradition/deity focus (skippable),
     preferred practice time, language]
                          │
         ["Your space is ready" → phone OTP, to save
                    the personalization]
                          │
        [Lands in a feed already shaped by the answers]
```
**Strength:** frames intent early ("why are you here") — fits a contemplative app's tone better than a generic content-app quiz would, and the personalization is genuinely used, not cosmetic.
**Weakness:** friction before value. Calm's own version of this quiz is explicitly skippable for exactly this reason — if adopted, that has to carry over here too.

### Option C: Ritual first (Duolingo pattern)

Duolingo's most important onboarding fact: **the streak starts inside onboarding, before signup even appears.** Pick a language, set a goal, complete a real placement lesson, commit to a streak — only then does account creation show up. The habit is the hook, not a feature discovered later.

```
[Opening screen states the one thing this app is for]
                          │
   ["Chant your first mala with us — 108, right now."
     A real, working Mala Ring counter — no login wall]
                          │
     [Completing it (or even part of it) → "Day 1 of
      your streak has started" — phone OTP requested
       specifically to save that progress, not before]
                          │
         [Only now does the feed appear]
```
**Strength:** the strongest possible "I'm already invested" moment, and it's tied directly to Anhad's actual differentiator (the japa tracker), not a generic content preview.
**Weakness:** a bigger ask than "let me just watch something" for a viewer who came to browse, not to commit.

### ⚠️ A caution worth stating plainly

Duolingo's playbook is proven, but not every part of it belongs here. Its mascot's guilt-tripping ("Duo is sad you missed a lesson") and its aggressive push toward forced widget installs are exactly the kind of manipulative pattern `FRONTEND_GUIDELINES.md` §8 already commits to avoiding — no streak-loss guilt language, no fake urgency. **Borrow the structure (an early win, tied to a returning habit) — not the execution (guilt, coercion).** Whichever option gets picked, run it back against that anti-pattern list before it ships.

### A hybrid worth considering

Rather than picking one option wholesale: land in real content immediately like Option A (speed, no upfront friction), but keep the Mala Ring persistently visible and inviting from the very first screen like Option C (the early-win hook), instead of gating everything behind Option B's quiz. Defer the phone OTP until the *first* save-worthy moment — either a Pranam or a completed chant session, whichever comes first — rather than a fixed point in a script. This keeps "show value before asking for anything" as the governing rule while still surfacing the habit loop early, without forcing a choice between speed and hook.

### Fixing the "renamed terms are confusing" problem specifically

This deserves its own answer, since it's a named concern (`GAPS.md`) and none of the three options above solve it by default. The research pattern that fits best is **progressive disclosure via first-encounter coach marks**, not an upfront glossary screen (which research on similar apps shows gets skipped or resented as a "wall"): the *first* time — and only the first time — a user sees each renamed action (Pranam, Satsang, Prasad, Smaran, Sevak), a small label appears beside it for that one encounter, then never again. Nobody has to read a legend before they can use the app; the explanation shows up exactly when it's needed and disappears once it's served its purpose.

---

## Creator onboarding

A different job: this isn't about a stranger discovering the app, it's about convincing someone who already has an Instagram/YouTube audience that switching is worth it. Two research findings apply directly:

**Frame the fee as access, not a toll.** Patreon's own positioning research is blunt about this: describing a payment as "support" implies the creator is asking a favor; describing it as "access" implies they're joining something. The ₹99 verification stake (`PRD.md` §7.5) should be presented as **unlocking Verified Artist status**, never as "a fee to post."

**Show it isn't an empty room before asking for money.** This is the cold-start problem `IMPLEMENTATION_PLAN.md` Phase 3 already solves at the content level (seed the Founding 50, seed the audio library) — but that solution needs to actually appear *in the creator signup screen itself*, not just exist in the backend. Concretely: show real existing creators and real engagement numbers as part of the "become a creator" screen, before the payment step, once the Founding 50 exist to show.

```
["Become a Verified Artist"]
                │
   [Screen showing real creators already here + real
    engagement numbers — not an abstract pitch]
                │
   [Draft your first reel now — category tag required,
    library audio available — before any payment screen]
                │
   [Pay the ₹99 verification stake, framed as unlocking
    Verified Artist status, with a visible 3-step tracker:
    "Post 1 of 3 clean reels to convert this into wallet
    credit" — shown as ongoing progress, not one buried
    line in the Terms of Service]
```
Letting a creator draft content *before* the payment prompt (Patreon skips forcing email verification up front for the same reason — invest effort first, ask second) means the payment moment arrives after they've already started, not before they've seen anything.

---

## Still needs a decision

This document intentionally stops short of picking one option — that's a founder call, not something to default into. Worth deciding:

1. Which Viewer onboarding direction (A / B / C / the hybrid) — or a different mix entirely.
2. Whether the coach-mark approach to the renamed-interaction confusion is the right fix, or whether a lighter first-open explainer card is preferred alongside it.
3. Timing: should Creator-mode discovery (the "become a Verified Artist" entry point) be visible to every Viewer from day one, or surfaced only after some engagement threshold?

Once these are settled, they should move into `PRD.md` §7 as the real spec, and this file's job is done.
