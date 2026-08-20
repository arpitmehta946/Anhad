DROP INDEX reels_created_at_idx;

ALTER TABLE reels DROP CONSTRAINT reels_category_check;
ALTER TABLE reels ADD CONSTRAINT reels_category_check
    CHECK (category IN ('bhajan', 'mantra', 'stuti', 'chalisa', 'aarti', 'discourse'));
