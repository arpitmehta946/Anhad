-- Schema-only reversal — the 'original'/'curator' values themselves aren't
-- recoverable once the column is dropped, same as 000006's own down
-- migration already accepts for the role split it undoes.

ALTER TABLE users ADD COLUMN creator_type TEXT;
ALTER TABLE users ADD CONSTRAINT users_creator_type_check
    CHECK (creator_type IS NULL OR creator_type IN ('original', 'curator'));
ALTER TABLE users ADD CONSTRAINT users_creator_type_requires_creator_check
    CHECK (creator_type IS NULL OR role = 'creator');
