# Frontend & Design Guidelines

**Companion to:** `PRD.md`, `TECH_STACK.md`
**Version:** 0.2
**Date:** August 20, 2026

## 1. The brief, stated plainly

The product this design serves is a vertical-video app for a single, specific act: singing or listening to a bhajan, mantra, or stuti. The design's one job is to make that act feel *protected* — like stepping into a temple courtyard, not like opening another feed. Every choice below is justified against that job, not against "what spiritual apps usually look like." Generic spiritual-app design defaults to two failure modes: pastel lotus-gradient New Age wellness clichés, or a straight Instagram reskin with folded-hands emoji bolted on. This system is deliberately neither.

---

## 2. Color

Grounded in the actual materials of the practice — diya flame, tulsi leaf, sindoor, sandalwood paper, the sky during evening aarti — rather than a generic "spiritual palette." Two full themes, not a light theme with a bolted-on dark inversion.

### Dusk — default theme
The sky in the minutes after sunset, when evening aarti happens. Chosen as default over a bright white app-shell background because it reads as contemplative rather than "app-like," and because it's genuinely easier on the eyes during the early-morning and evening sessions this product is built around.

| Token | Hex | Use |
|---|---|---|
| `bg-base` | `#1B1730` | Primary background |
| `bg-surface` | `#2E2347` | Cards, sheets, elevated panels |
| `text-primary` | `#F3EADD` | Body and heading text on dark ground |
| `text-secondary` | `#B8A78E` | Captions, timestamps, muted labels |

### Prabhat — light theme (equal citizen, not an afterthought)
Warm manuscript-paper tones for daytime and outdoor use, and for anyone who reads better on light backgrounds.

| Token | Hex | Use |
|---|---|---|
| `bg-base` | `#FBF3E4` | Primary background |
| `bg-surface` | `#F3E7CE` | Cards, sheets, elevated panels |
| `text-primary` | `#2B2418` | Body and heading text |
| `text-secondary` | `#7A6F58` | Captions, timestamps, muted labels |

### Shared accents (both themes)

| Token | Hex | Name | Use |
|---|---|---|---|
| `accent-primary` | `#E8A33D` | **Diya** (marigold / turmeric) | Primary buttons, active states, the Pranam icon, progress fills |
| `accent-success` | `#7A9471` | **Tulsi** (sage) | Verified-artist badge, completed streak days, positive confirmations |
| `accent-alert` | `#C4463A` | **Sindoor** | Reserved *exclusively* for destructive actions and true errors — never for notification badges, streak-loss pressure, or urgency gimmicks. See §8. |

Do not substitute a cream-and-terracotta palette (near `#F4F1EA` background with a `#D97757`-family clay accent) — it's become a recognizable AI-generated-design default and will read as generic rather than intentional. Do not default to pastel purple/pink lotus gradients — that's the wellness-app cliché this product should read as more serious than.

---

## 3. Typography

Two roles, deliberately paired — not the same system-default sans used everywhere:

- **Display (headings, the artist name on a reel, section titles):** **Fraunces** — a serif with warmth and a slightly calligraphic character at larger sizes, used with restraint (headings and emphasis only, never body paragraphs). It gives the app presence without leaning on literal Devanagari-mimicking Latin letterforms, which reads as costume rather than craft.
- **Body & UI (captions, buttons, the whole interface chrome):** **Work Sans** — clean, highly legible at small sizes, warm enough to sit comfortably next to Fraunces without fighting it.
- **Devanagari and other Indic scripts (mantra/lyric text, Sanskrit, Hindi):** **Noto Sans Devanagari** (UI) and **Noto Serif Devanagari** (displayed verses/lyrics) as first-class citizens, not a fallback font swapped in when Latin fails. A meaningful share of the actual content in this app *is* Devanagari text — verify both typefaces at the sizes used for on-screen lyric display before locking the type scale, since Devanagari needs more vertical line-height than Latin to avoid clipped matras.

Type scale: set a clear, restrained hierarchy (e.g., display/H1 at 28–32px, H2 at 22px, body at 16px, caption at 13px) and hold to it — don't let individual screens invent one-off sizes.

---

## 4. Layout concept

Full-bleed vertical video is the canvas (the reel itself), consistent with the format users already know from Reels/Shorts — there's no reason to reinvent that part. What should feel different is the **chrome around it**: action buttons, category chips, and cards use a soft-arched top edge (a shallow curve, not a full gopuram silhouette — subtle enough to not be kitsch) rather than the sharp rounded-rectangle pill shape every social app defaults to. This is a quiet, consistent structural signal that the interface itself, not just the icons, was designed for this content.

---

## 5. Signature element: the Mala Ring

One motif, reused across three functional contexts, is the single most memorable thing in this design:

A circular ring of small beads — visually a japa mala — used as:
1. **The japa counter's progress visualization** — beads fill in (highlight in Diya gold) one at a time as the user chants, in groups readable at a glance, rather than a smooth arc. This is the actual practice made visible, not a generic circular progress bar borrowed from a fitness app.
2. **The streak tracker** — each of the 21 days in a streak is one bead on a longer ring; completed days are filled, today's bead pulses gently.
3. **The loading/processing indicator** — a small version of the same bead ring, animating one bead lighting up after another, used everywhere else in the app a spinner would normally go.

Reusing this one shape everywhere a generic app would use three different unrelated UI patterns (a progress bar, a streak calendar grid, a spinner) is what makes the app feel *made for this*, rather than assembled from a component library.

The arrival screen's Sapta Swara sequence (§12) resolves into this exact ring when the user taps "Begin" — a second signature element that ends by becoming the first one, not a competing visual language.

---

## 6. Motion

Slow, breathing easing curves (300–500ms ease-in-out) — not the snappy 150ms spring animations typical of gamified or dopamine-loop apps. The Mala Ring's bead-fill on each japa tap uses a soft pulse (scale 1.0 → 1.03 → 1.0) timed loosely to a breath cycle, not a sharp "ding" snap. Reduced-motion settings must be respected everywhere, not just as an OS-level afterthought — this audience skews toward users who may have reduced-motion needs more often than a typical consumer app's audience.

---

## 7. Iconography & renamed interactions

Full naming rationale lives in `PRD.md` §6 — this is the visual treatment.

| Action | Name | Icon direction |
|---|---|---|
| Like | Pranam 🙏 | Custom line-icon of folded hands — not a generic heart, and not a literal emoji rendered at UI scale |
| Comment | Satsang 💬 | A speech shape built from a soft lotus-petal silhouette, distinct from a generic chat bubble |
| Share | Prasad 🍃 | A leaf/offering shape |
| Remix/Duet | Jugalbandi 🪕 | Two interlocking curved lines suggesting a duet, not a literal instrument icon |
| Save | Smaran 📿 | A single mala bead |
| Follow | Sevak 🌸 | A small flower/circle mark |

Build these as a custom icon set early — do not ship generic Material/Cupertino icons re-labeled with new text, since the icon shape itself is part of what signals "this isn't Instagram."

Accessibility labels must use the *functional* meaning for screen readers ("Save this reel," not "Smaran this reel") so the renamed interactions don't create a barrier for assistive technology — the poetic name is a visual/brand layer, not a replacement for a clear accessible label.

---

## 8. Anti-patterns — do not build these

This list exists because every one of these is a default pattern in mainstream social apps, and building this product means deliberately not reaching for them:

- **No red pulsing notification badges.** Use the Diya gold accent, at low visual weight, for new-activity indicators. Sindoro-red is reserved for actual errors and destructive actions only (§2).
- **No infinite autoplay countdown into the next reel.** A gentle stopping point ("You've spent 10 mindful minutes today") is a feature, not a missing feature.
- **No streak-loss guilt language.** "You lost your streak" framing is a dark pattern borrowed from gamified habit apps; use neutral, re-inviting language instead ("Start a new streak today" rather than "You broke your streak").
- **No fake urgency on subscription upsells.** No countdown timers, no "only 3 spots left" — the Seva Pass pitch should rest on genuine utility (background playback, offline audio), not manufactured scarcity.
- **No gamifying spiritual progress with payment.** Trust scores, mala-count milestones, and streak badges must never be purchasable — only *convenience* features (lock-screen playback, offline downloads) are ever behind a paywall. See `PRD.md` §10.3.

---

## 9. Voice & copy

- Plain verbs, active voice, sentence case. A button that says "Save changes" produces a confirmation that says "Saved" — the vocabulary stays identical through a whole flow, which is how people learn their way around an interface without thinking about it.
- Name things by what the person is doing, not by the underlying system: "Choose a category," not "Set content classification metadata."
- Empty states are an invitation, not an apology: a new user's empty feed before content loads should read as a beginning, not an error.
- Moderation messaging (a held or rejected upload) states what happened and what to do next, plainly — it doesn't scold, and it doesn't hide behind vague "violates guidelines" language without specifics.

---

## 10. Screen-specific guidance

- **Feed:** minimal chrome over the reel; the Mood/Vibe switcher (`PRD.md` §7.1) is a persistent pill row at the top, not buried in a settings menu — it's a primary navigation surface, not an advanced option.
- **Japa counter:** the Mala Ring dominates the screen; the numeric count is secondary to the visual. Large tap target if the screen is on; the screen-off flow relies entirely on hardware volume-key interception (`TECH_STACK.md` §2) with haptic-only feedback.
- **Upload flow:** category selection is a required step the user cannot skip past, presented as a simple single-choice list, not a searchable dropdown — the fixed category list (`PRD.md` §4.1) is short enough not to need search.
- **Profile:** trust score and badges are shown as quiet, factual markers (a small Tulsi-green check for Verified Artist) — not a game-style stat block with levels and XP bars, which would undercut the "you cannot buy or grind devotion" principle.
- **Audio library:** waveform preview plus the metadata that actually helps a creator choose (deity, raga, tempo, mood) — browsable by category, searchable by name.

---

## 11. Accessibility floor

- All icon-only actions carry proper screen-reader labels using plain functional language (§7).
- Color contrast meets WCAG AA in both themes — verify Diya gold on both `bg-base` tokens specifically, since gold-on-dark and gold-on-light have different contrast margins.
- Text scales with system font-size settings without breaking layout; this matters more than usual here given the likely age range of some users (the existing competitor research in `PRD.md` §3.3 repeatedly notes "simple interface for elders" as a valued feature).
- Reduced-motion setting disables the Mala Ring's pulse animation and any autoplay transitions, substituting an instant state change.
- Multi-script text (Devanagari + Latin mixed in captions or bios) renders correctly without clipping or reflow bugs — test this explicitly, it's a common failure point.

---

## 12. Signature element: Sapta Swara

The arrival screen (`ONBOARDING.md` §3, screen 1) needed its own visual, and the obvious default — a devotee figure bowing, praying, or dancing — was deliberately rejected: every devotional app already has one. What's actually distinctive to Anhad is the idea underneath the name itself.

**The concept.** *Sapta swara* — the seven notes (Sa Re Ga Ma Pa Dha Ni) every bhajan, kirtan, and mantra melody is built from. Not a japa-specific idea like the Mala Ring; this is the app's melodic alphabet, arising on its own. Seven thin rings expand outward from seven points on the screen, one per swara, in ascending scale order — each a single voice; where two overlap, they brighten together rather than merge into a mass (`BlendMode.screen`, not simple alpha) — sangat, many voices as one.

**No source object.** No hand, bell, striker, or figure anywhere in the scene. "Anhad" names *anahata nada* — the unstruck sound, produced by nothing striking anything. The rings simply arise; nothing causes them.

**Layout.** Positions run bottom-to-top, scattered rather than gridded, following the Sangita Ratnakara's description of nada rising through the body — navel, heart, throat, tongue, nose, teeth, lips:

| Swara | Position (x, y) | Color | Ratio to Sa |
|---|---|---|---|
| Sa | 50%, 84% | `#E8A33D` (gold) | 1/1 |
| Re | 26%, 73% | `#D4826B` | 9/8 |
| Ga | 72%, 62% | `#C1739A` | 5/4 |
| Ma | 32%, 48% | `#8E86C6` | 4/3 |
| Pa | 64%, 36% | `#F2C46B` (gold) | 3/2 |
| Dha | 36%, 24% | `#7FA88C` | 5/3 |
| Ni | 60%, 13% | `#6FA0B8` | 15/8 |

Sa and Pa are both gold — they're the *achala* (fixed) swaras every raga returns to, regardless of which raga is being sung; the other five each get their own warm, desaturated hue. Not a chakra-rainbow palette — that's the New Age cliché this whole system exists to avoid (§2).

**Motion.** Each ring runs an independent 6.4s cycle — 18px start diameter expanding to ~4.6× via `cubic-bezier(.17,.62,.31,1)`, opacity rising to 0.8 by 9% through the cycle, fading to 0.26 by 55%, gone by 100% — offset from the others by 0.9s per swara in scale order. Because every ring shares the same period, that stagger holds forever, not just on first paint: the sequence keeps arising continuously for as long as someone stays on the screen. Center stage is the Mala Ring itself (§5) at 120px, breathing gold rather than showing tap progress, with a soft radial glow behind it swelling on the same 5.2s cycle as the ring — "one motion language across the app" (§6), not a second rhythm competing with the first.

**Sound.** The seven tones play every time this screen is shown — this is the arrival screen for every app open, not a first-run-only moment (see "Always shown" below). Just intonation relative to Sa (136.1 Hz: Sa 1/1, Re 9/8, Ga 5/4, Ma 4/3, Pa 3/2, Dha 5/3, Ni 15/8), not equal temperament — this is what makes it sound Indian rather than like a piano. Pitched an octave below where this started (272.2 Hz) — at the higher octave the tone read as bright and harsh rather than melodious, and dropping it a full octave kept even the upper harmonics of Ni, the highest swara, in a warm range. A soft, rounded timbre (fundamental plus two gentle overtones, deliberately not a bright buzz) with a gentle sine-eased attack and a long decay lets the notes overlap and ring together instead of sounding staccato, each firing exactly as its ring begins expanding. Synthesized on-device (Dart) rather than shipped as audio assets. Unlike the completion bell (`ONBOARDING.md` §5 item 1), this plays on the phone's built-in speaker specifically — forced there natively regardless of a connected Bluetooth device (`SaptaSwaraPlayer.kt`), since it's meant to be heard right away rather than silently landing on a paired speaker or earbuds nobody has in yet — but it still respects the device's silent/vibrate switch, animating without sound if silenced.

**Resolution.** Tapping "Begin" doesn't cut to the next screen — the ripples settle inward and resolve into the Mala Ring, the same circle carried forward into the japa counter itself. Two signature elements, not two visual languages. Where "Begin" then leads depends on how far along the person already is (still mid first-run flow, done with it but signed out, or fully signed in) — this screen only handles the arrival moment, not the branching after it.

**Always shown.** Unlike the rest of the first-run flow (screens 2–4, which are genuinely one-time), this screen is the app's arrival moment on *every* open, not gated behind a "seen it once" flag. A returning, already-onboarded user sees the same seven rings and hears the same seven notes each time, then "Begin" takes them straight into practice or the signed-in app rather than back through onboarding.

**Reduced motion.** Rings render static at varied scales (not one frozen frame — still seven distinct sizes) and flat 0.3 opacity; the center ring and glow hold at fixed opacity with no breathing; no sound plays.
