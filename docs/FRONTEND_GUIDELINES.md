# Frontend & Design Guidelines

**Companion to:** `PRD.md`, `TECH_STACK.md`
**Version:** 0.1
**Date:** August 16, 2026

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
