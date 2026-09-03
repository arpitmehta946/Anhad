-- Wires the reel upload/moderation flow into the existing audio_library
-- table (migration 000003, docs/TECH_STACK.md §6) so "every uploaded
-- reel's audio becomes reusable and attributed" (docs/PRD.md §7.3) is
-- real, not just that table's original seeded-library-only shape —
-- internal/reels.Service's own doc on jugalbandi_reuse_count (migration
-- 000011) already named this table as where real audio-reuse tracking
-- belongs, once something actually wrote to it.

-- source_reel_id is NULL for a seeded/curated track (Tanpura drones,
-- temple bells — docs/PRD.md §7.3's other P0 half, still unbuilt) and set
-- for a track derived from a creator's own reel. The two share this table
-- because they're the same real-world thing — a reusable audio track with
-- an attributed rights-holder — not two concepts that only look similar.
ALTER TABLE audio_library ADD COLUMN source_reel_id UUID UNIQUE REFERENCES reels(id) ON DELETE CASCADE;

-- Library visibility (docs/PRD.md §4.5) — a minor performer's audio
-- defaults to excluded from both browsing and reuse, parent opt-in only.
-- Same always-present boolean-gate shape as reels.jugalbandi_enabled
-- (migration 000011) rather than conditionally skipping row creation, so
-- a parent can flip this on later with no backfill needed.
ALTER TABLE audio_library ADD COLUMN is_public BOOLEAN NOT NULL DEFAULT true;

-- A reel-derived track's title was never guaranteed — a reel's own
-- caption (internal/reels.Reel.Caption) is optional. The original NOT
-- NULL assumed only curated entries with a real title would ever land
-- here.
ALTER TABLE audio_library ALTER COLUMN title DROP NOT NULL;

-- The category list drifted: this table predates migration 000007's
-- category rework and still only allowed the old 'discourse' value, not
-- the four categories reels actually use today. Left unfixed, every
-- kirtan/sant_vani/meditation_naad reel would fail to publish a track.
ALTER TABLE audio_library DROP CONSTRAINT audio_library_category_check;
ALTER TABLE audio_library ADD CONSTRAINT audio_library_category_check
    CHECK (category IN ('bhajan', 'mantra', 'stuti', 'chalisa', 'aarti', 'kirtan', 'sant_vani', 'meditation_naad'));

CREATE INDEX audio_library_public_category_idx ON audio_library(category, created_at DESC) WHERE is_public;

-- Per-reel opt-in/out (docs/PRD.md §4.5, §7.3), resolved at reel-creation
-- time in internal/reels.CreateReel the same way jugalbandi_enabled
-- already is, then read back once the reel is later approved and its
-- audio_library row actually gets created (internal/audio.Service) — needs
-- its own column rather than resolving straight into audio_library.is_public
-- at upload time, since track creation happens later, asynchronously,
-- after moderation.
ALTER TABLE reels ADD COLUMN audio_library_enabled BOOLEAN NOT NULL DEFAULT true;

-- "Use this sound" (docs/PRD.md §7.3) marks a reel as built from an
-- audio_library track using reels.audio_id — already there since migration
-- 000004's original schema pass (docs/TECH_STACK.md §6), indexed, with its
-- own ON DELETE RESTRICT, but never written to until now. No new column
-- needed: it's the same relationship this migration's other half
-- (audio_library.source_reel_id) points back from, just the direction
-- nothing had wired up yet.
