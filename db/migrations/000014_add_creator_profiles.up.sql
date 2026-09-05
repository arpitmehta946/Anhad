-- Creator profile pages: Sevak (follow, migration 000010) previously led
-- nowhere — there was no page to land on. Adds the fields a profile shows
-- beyond what users already had (display_name, avatar_url): a stable
-- @handle, a short bio, and a Verified Artist marker.

-- Nullable and backfilled lazily by internal/profile.Service the first
-- time a profile is fetched, not by this migration — a handle needs to be
-- unique and there's no meaningful value to generate in bulk SQL that's
-- better than what the application already knows how to do per-row on
-- demand.
ALTER TABLE users ADD COLUMN handle TEXT UNIQUE;

-- Capped at 160 characters (bio, not an essay) — enforced here too, not
-- just client-side, since this column has no other guard against an
-- arbitrarily long value.
ALTER TABLE users ADD COLUMN bio TEXT CHECK (bio IS NULL OR char_length(bio) <= 160);

-- Shown as a quiet factual marker (docs/FRONTEND_GUIDELINES.md §10), not
-- tied to any automated check — docs/PRD.md §8.5's verification bar is
-- still undefined (docs/GAPS.md), so this is settable only by an
-- admin/moderator directly today, the same "real column, no grant-UI yet"
-- shape as is_founding_creator (migration 000006).
ALTER TABLE users ADD COLUMN is_verified_artist BOOLEAN NOT NULL DEFAULT false;
