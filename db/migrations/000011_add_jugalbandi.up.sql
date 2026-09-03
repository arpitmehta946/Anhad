-- Jugalbandi (remix/duet, docs/PRD.md §7.2) and its permission model
-- (docs/PRD.md §4.5): recording alongside an existing reel.

-- is_minor_performer_account marks a Family Account (docs/PRD.md §4.5) —
-- there is no separate "child user" row to link to: per §4.5, the parent
-- *is* the account holder ("The parent is the legal account holder... The
-- child is the credited performer"), so a minor performer never has their
-- own login to gate anything behind. No signup path can set this true yet
-- — Family Accounts are design-only in PRD.md, not built (docs/GAPS.md
-- already tracks this: save_practice_screen.dart's under-18 declaration
-- deliberately ends without creating an account at all). This column, and
-- the default-off Jugalbandi behavior it drives (internal/reels.CreateReel),
-- are real, forward-compatible enforcement of the rule — just currently
-- unreachable because no minor-performer account can exist to trigger it,
-- not a stub pretending to be one.
ALTER TABLE users ADD COLUMN is_minor_performer_account BOOLEAN NOT NULL DEFAULT false;

-- Per-reel Jugalbandi permission — an ordinary adult creator's default is
-- "allowed," a minor-performer account's default is "off," set explicitly
-- by internal/reels.CreateReel at insert time (not expressible as a plain
-- column DEFAULT, since it depends on the creator's own row). Whoever
-- already controls the reel (the account holder — the parent, by
-- construction, for a Family Account) is the only one who can flip it,
-- the same as any other creator-owned reel setting; no separate
-- parent-permission gate is needed on top of that.
ALTER TABLE reels ADD COLUMN jugalbandi_enabled BOOLEAN NOT NULL DEFAULT true;

-- jugalbandi_source_id marks a reel as a duet result, pointing at the
-- original it was recorded alongside. ON DELETE SET NULL rather than
-- CASCADE or RESTRICT: reel deletion isn't built yet (docs/GAPS.md), but
-- when it is, losing the source shouldn't silently delete someone else's
-- duet performance, and blocking the source's own deletion just because a
-- duet references it is too strict a coupling.
ALTER TABLE reels ADD COLUMN jugalbandi_source_id UUID REFERENCES reels(id) ON DELETE SET NULL;

-- The concrete, buildable half of docs/PRD.md §7.3's "audio-reuse counter
-- visible to the original artist" for this path — incremented on the
-- *source* reel each time a Jugalbandi is recorded against it. The full
-- audio_library-keyed version (play_count/reuse_count on audio_library
-- itself) needs the seeded-audio-library upload flow first, which isn't
-- built (docs/CLAUDE.md); this is reel-level, not audio-track-level, but
-- it's real, live data the future royalty engine (docs/PRD.md §10.4) can
-- read once audio_library is wired to reels at all.
ALTER TABLE reels ADD COLUMN jugalbandi_reuse_count BIGINT NOT NULL DEFAULT 0 CHECK (jugalbandi_reuse_count >= 0);

CREATE INDEX reels_jugalbandi_source_id_idx ON reels(jugalbandi_source_id);
