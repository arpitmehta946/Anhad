-- Updates reels.category to the August 18 scope decision (docs/PRD.md
-- §4.1): Katha/Discourse dropped, Kirtan / Sant Vani / Meditation & Naad
-- added. audio_library.category is deliberately left alone here — the
-- audio-reuse library isn't part of this slice and touching its
-- constraint now would be an unrelated, unverified change.

ALTER TABLE reels DROP CONSTRAINT reels_category_check;
ALTER TABLE reels ADD CONSTRAINT reels_category_check
    CHECK (category IN ('bhajan', 'mantra', 'stuti', 'chalisa', 'aarti', 'kirtan', 'sant_vani', 'meditation_naad'));

-- The existing reels_category_created_at_idx (migration 000004) only
-- serves a category-filtered feed query — an unfiltered "all categories"
-- request needs its own plain created_at ordering to stay index-backed.
CREATE INDEX reels_created_at_idx ON reels(created_at DESC) WHERE moderation_status = 'approved';
