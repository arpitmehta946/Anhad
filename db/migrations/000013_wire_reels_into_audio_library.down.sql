ALTER TABLE reels DROP COLUMN audio_library_enabled;

DROP INDEX audio_library_public_category_idx;

ALTER TABLE audio_library DROP CONSTRAINT audio_library_category_check;
ALTER TABLE audio_library ADD CONSTRAINT audio_library_category_check
    CHECK (category IN ('bhajan', 'mantra', 'stuti', 'chalisa', 'aarti', 'discourse'));

-- A row inserted while title was nullable has no real value to backfill —
-- same acceptable gap 000012's own down migration accepts for its column —
-- but SET NOT NULL below would fail outright against an existing NULL, not
-- just lose data, so it needs a placeholder first.
UPDATE audio_library SET title = 'Untitled' WHERE title IS NULL;
ALTER TABLE audio_library ALTER COLUMN title SET NOT NULL;

ALTER TABLE audio_library DROP COLUMN is_public;
ALTER TABLE audio_library DROP COLUMN source_reel_id;
