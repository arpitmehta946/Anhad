-- Seeded audio library (docs/PRD.md §7.3 P0, IMPLEMENTATION_PLAN.md Phase 3):
-- platform-owned tracks (tanpura drones, temple bells, harmonium scales,
-- Vedic chant loops, ambient soundscapes) so a brand-new creator can post
-- within 30 seconds of signing up, without already having a complete
-- original recording of their own. These aren't anyone's performance, so
-- they get no artist row at all — attributing them to a fake "Anhad" user
-- would make the royalty pool (docs/PRD.md §10.4, which splits among real
-- creators only) have to explicitly exclude that one account forever;
-- artist_id simply being NULL is a cleaner, harder-to-misuse signal that a
-- future royalty batch job excludes with a plain "WHERE artist_id IS NOT
-- NULL" rather than a magic-UUID exclusion list.

ALTER TABLE audio_library ALTER COLUMN artist_id DROP NOT NULL;

ALTER TABLE audio_library ADD COLUMN is_platform_track BOOLEAN NOT NULL DEFAULT false;

-- Keeps artist_id's nullability and is_platform_track in lockstep so the
-- two can never drift into an ambiguous state (a NULL artist_id that
-- isn't marked platform, or a platform track that somehow has an artist) —
-- belt-and-suspenders over relying on "artist_id IS NULL" alone to mean
-- platform-owned everywhere downstream.
ALTER TABLE audio_library ADD CONSTRAINT audio_library_platform_ownership_check
    CHECK ((is_platform_track AND artist_id IS NULL) OR (NOT is_platform_track AND artist_id IS NOT NULL));

-- A platform track is curated, not user-generated — internal/audio.Service's
-- own doc on PublishTrackForReel explains why every *other* row in this
-- table only exists once its source reel clears the three-layer moderation
-- pipeline (docs/PRD.md §8.1). These skip that pipeline entirely (nothing
-- to moderate: we sourced the recording ourselves), inserted straight by
-- cmd/seedaudio, never through a reel upload.
