# Onboarding & The Returning Experience

**Companion to:** `USER_FLOWS.md`, `FRONTEND_GUIDELINES.md`, `PRD.md`
**Version:** 0.1 — research findings + recommended flow
**Date:** August 18, 2026

This supersedes the open question in `USER_FLOWS.md` for the **japa** side of the app specifically (the feed's onboarding is still open, since no feed exists yet). It is grounded in a scan of ~15 competing japa/mala counter apps on Google Play and the App Store, and in what their actual users complain about in reviews.

---

## 1. What the competitor scan actually found

### 1.1 The onboarding gap — the real opportunity

Every japa counter app reviewed falls into one of two camps:

- **Bare counter, zero context.** You open it and there's a number and a button. No explanation, no welcome, no sense of what this is for. Most free apps.
- **Configure-before-you-chant.** Set your mantra, pick your deity image, choose your mala length, set a target — *then* you may begin. Several of the more featured apps.

**Nobody makes the first sixty seconds a practice.** That's the gap. A first-time user's first act should be chanting, not configuring and not staring at an unexplained number. This is what the "ritual first" option in `USER_FLOWS.md` was reaching for, and the competitor scan confirms nobody in this category has taken it.

### 1.2 What users actually complain about

Direct from reviews of live japa apps — these are the failure modes to design against:

| Complaint | The actual review | Design implication |
|---|---|---|
| **Lost streaks are devastating** | A user losing a 45–55 day streak wrote several crying emoji and threatened to uninstall with a bad review — twice in one review | Streak loss is the single most emotionally charged failure in this category. Anhad's atomic-write and 429-throttle fixes already address the data side; the *display* must never imply loss either |
| **Progress doesn't survive a new phone** | One reviewer noted their count didn't carry to a new device despite logging in with the same phone number, calling it "not a good operative system" | Anhad's server-side sync already solves this — **and it's a genuine competitive advantage worth stating in onboarding**, since most competitors are local-only |
| **Ads in a sacred space** | "From 5★ to 1★ real quick. Paid user here, and you still made me watch 3 ads just to set a photo." Another uninstalled over ad volume despite it being their favourite app | `PRD.md` already commits to no interstitial ads. Worth saying so explicitly at first run — it's a real differentiator users care about intensely |
| **Screen brightness during long sessions** | "Please add dark screen option as we're looking at the screen constantly" | Anhad's Dusk theme handles this by default. A true black focus mode is worth considering |

### 1.3 Table-stakes features Anhad is currently missing

These appear across most competing apps. Their absence will be noticed — several relate directly to eyes-closed chanting, which is how japa is actually practised:

1. **Completion bell.** A soft singing-bowl tone when a mala completes. One app describes this precisely: it rings *"so you can keep your eyes closed and stay in the flow."* This is the highest-value missing feature — Anhad currently gives no eyes-closed confirmation that a round finished.
2. **Undo.** A mis-tap currently can't be corrected. Nearly every competitor has this.
3. **Custom mala length.** 108 is the default, but 27 (quick), 54 (half), and 1008 (extended) are standard practice. Currently hardcoded to 108.
4. **Lifetime total** alongside today's count — nearly universal in competitors, and Anhad has the data already.
5. **Mantra text on screen.** Several apps display the mantra above the counter *"so that you don't forget long or difficult mantra."*
6. **Deity image.** The most-requested personalization across every app reviewed — users want to chant while looking at their chosen deity.
7. **History view.** Weekly charts or a calendar heat-map of practice.

Items 1–3 are small and directly affect the core loop. Items 5–6 are personalization that can wait, but they're clearly what this audience wants.

---

## 2. The idea worth building the whole thing around: Sankalp

This is the strongest finding in the research, and it reframes a feature Anhad has already built.

**Anushthan** is a vowed, systematic spiritual undertaking: a predetermined total of mantras, divided into daily portions, chanted without break across a fixed number of days — commonly **11, 21, or 36**. The vow kept faithfully each day is precisely what distinguishes it from ordinary worship. **Sankalp** is the vow itself — stating your name, your intention, and what you undertake, before you begin. As one practitioner's phrasing has it: a ritual without sankalp is like an arrow without a target.

**Anhad already built a 21-day streak with a reward at completion** (`PRD.md` §7.4, §10.3). That structure is not merely *similar* to an anushthan — it is one. But it's currently framed in the borrowed vocabulary of habit-tracking apps.

Reframing the streak as a **Sankalp** does three things at once:

1. **It makes the mechanic culturally native rather than imported.** A 21-day streak is Duolingo. A 21-day sankalp is a practice with centuries behind it, which this audience already understands and takes seriously.
2. **It solves the anti-pattern problem in `FRONTEND_GUIDELINES.md` §8.** The guidelines forbid streak-loss guilt language. Sankalp gives a genuinely better frame: a vow that lapses isn't a punishment or a lost score — it's simply renewed. "Begin a new sankalp" is honest, non-manipulative, and traditionally accurate.
3. **It's the differentiator no competitor has.** Every app has streaks. None frame practice as a vow with an intention attached to it.

**Design implication:** offer 11 / 21 / 36-day sankalp lengths (the traditional options), let the user optionally state an intention when taking one, and show that intention when they return. Someone who wrote *"for my mother's health"* on day one and sees it on day fourteen is having an experience no habit-tracker can replicate.

---

## 3. Recommended first-run flow

Four screens. No account required to reach the chanting.

```
┌─ 1. ARRIVAL ──────────────────────────────────────────────┐
│  Dusk theme. The Mala Ring, unfilled, breathing gently.   │
│  One line: "A quiet space for japa."                      │
│  One button: "Begin"                                       │
│  No signup. No quiz. No feature tour.                     │
└───────────────────────┬───────────────────────────────────┘
                        ▼
┌─ 2. THE FIRST MALA ───────────────────────────────────────┐
│  Straight into a working counter. One hint, once:         │
│  "Tap anywhere. Or use your volume keys with the          │
│   screen off."                                             │
│                                                            │
│  At bead 108: the completion bell rings, the ring fills   │
│  fully, one held moment before anything else appears.     │
│  → This is the emotional peak. Don't rush past it.        │
└───────────────────────┬───────────────────────────────────┘
                        ▼
┌─ 3. THE SANKALP OFFER (first real choice) ────────────────┐
│  "You've completed one mala.                              │
│   Would you like to take a sankalp?"                      │
│                                                            │
│  [11 days] [21 days] [36 days]  ·  [Not now]              │
│  Optional, one line: "What is this practice for?"         │
│                                                            │
│  "Not now" is a real option, not a dark pattern —         │
│  they keep everything they just did.                      │
└───────────────────────┬───────────────────────────────────┘
                        ▼
┌─ 4. SAVE IT (the only ask) ───────────────────────────────┐
│  "Save your practice so it's here tomorrow —              │
│   and on any phone you sign in from."                     │
│  → Phone OTP                                              │
│                                                            │
│  Framed as protecting what they already have, not as      │
│  a gate before they can start. Directly answers the       │
│  device-migration complaint in §1.2.                      │
└───────────────────────────────────────────────────────────┘
```

**Why signup lands at step 4 and not step 1:** deferred signup measurably lifts activation (`USER_FLOWS.md` §Why this matters), and by this point the user has something worth protecting. The ask is honest rather than obstructive.

**One thing to state plainly somewhere in this flow:** no ads, ever. Given how violently users react to ads in devotional apps (§1.2), this is worth saying rather than merely doing.

---

## 4. The returning experience — "praised every time"

First-run happens once. The other 364 days are what actually determine whether someone loves this app, and it's where most competitors stop putting in effort.

**Open to the practice, not to a dashboard.** Returning users should land on the Mala Ring, ready to chant, not on a stats page. Everything else is one tap away.

**Time-aware, quietly.** Anhad knows the hour. Before dawn, *Brahma muhurta* (roughly 4–6am) is traditionally the most auspicious time for japa — acknowledging that with a single line, not a banner, tells the user the app understands the practice. Evening aarti time likewise. One line, never a notification, never a nag.

**Never show a bare zero.** The first thing shown at 6am shouldn't be "0 chants today." Show the sankalp instead — *"Day 14 of 21"* — and their own stated intention beneath it. Today's zero is then obviously the beginning of something, not an absence.

**Continuity across days.** Their intention from day one, resurfacing on day fourteen, is the single most memorable thing this app can do. No competitor does it.

**The completion bell is the signature sound.** A distinctive, warm, unmistakable tone at mala completion. Heard hundreds of times with eyes closed, it becomes the app's identity more than any visual element — this is worth genuine effort in sound selection, not a stock chime.

**When a sankalp lapses** (`FRONTEND_GUIDELINES.md` §8 governs this):
- Never: "You lost your streak," crying imagery, red badges, guilt.
- Instead: *"Your sankalp of 21 days ended at day 14. 1,512 chants — those remain yours. Begin again?"*
- The count already earned is never erased or diminished. This directly counters the most emotionally charged complaint in the category.

---

## 5. Build order

1. **Completion bell + haptic on mala completion** — smallest change, biggest experiential gain, and required for eyes-closed practice
2. **Undo, custom mala length (27/54/108/1008), lifetime total** — table stakes, all small
3. **Sankalp reframing** — rename the existing streak feature, add 11/21/36 options and the optional intention field
4. **First-run flow** — the four screens above
5. **Returning-experience polish** — time-aware line, sankalp-first display, lapse copy
6. **Later:** deity image, mantra text display, history charts, focus mode

Items 1 and 2 are worth doing before the first-run flow, since the first run *depends* on the completion bell landing well.

---

## 6. Still open

- **Feed onboarding** remains undecided (`USER_FLOWS.md`) — it can't be settled until the feed exists.
- **Sankalp ↔ Seva Pass interaction:** `PRD.md` §10.3 grants a 7-day trial at 21 days. Does completing a *sankalp* grant it, and do 11- and 36-day sankalps grant anything different? Needs a decision before implementation.
- ~~**Tradition scope**~~ — ✅ **resolved August 18, 2026** (`PRD.md` §4.4). Content scope is Sanatan/Hindu, all sampradayas served, seeded Hindi/Sanskrit/North-Indian first. Sankalp vocabulary is therefore correct as written and needs no hedging — it is native to the tradition the platform serves, not a borrowed term requiring translation for other faiths.

## 7. Onboarding implications of the August 18 scope decisions

Three decisions in `PRD.md` §4 change what the first-run flow must handle:

- **Age gating (`PRD.md` §4.5).** The flow in §3 already defers signup until after the first mala, which is exactly right for DPDPA: a child can watch and chant with no account and therefore no data processed. But **step 4 (the OTP ask) is now an age gate** — it needs an age declaration, routing under-18s to either verifiable parental consent or the Family Account path. That's a new screen, not a field.
- **Family Accounts (`PRD.md` §4.5).** A parent setting up an account for a child singer is a genuinely different onboarding path — parent KYC, child's performing name, comment and visibility defaults. It should not be bolted onto the standard creator flow.
- **Singing-only scope (`PRD.md` §4.1).** Any onboarding copy or category picker referencing katha, pravachan, or darshan is now wrong. The arrival screen's promise should be about *singing and reciting*, not devotional content generally.
