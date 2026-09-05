-- Optional creator identity fields — tradition/sampradaya, lineage,
-- languages, instruments. Distinct from bio (migration 000014): these are
-- structured facts about who taught someone and what tradition they sing
-- in, not a free-form sentence, and worth their own fields so the profile
-- can show them as a small identity block rather than buried in prose.
-- All optional — an empty array/null column is a creator who hasn't
-- filled these in, not an error.

ALTER TABLE users ADD COLUMN tradition TEXT
    CHECK (tradition IS NULL OR char_length(tradition) <= 80);
ALTER TABLE users ADD COLUMN lineage TEXT
    CHECK (lineage IS NULL OR char_length(lineage) <= 120);
ALTER TABLE users ADD COLUMN languages TEXT[] NOT NULL DEFAULT '{}'
    CHECK (cardinality(languages) <= 10);
ALTER TABLE users ADD COLUMN instruments TEXT[] NOT NULL DEFAULT '{}'
    CHECK (cardinality(instruments) <= 10);
