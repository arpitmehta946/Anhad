-- creator_type (added in 000006) is dead: PRD.md §10.2 retired the curator
-- role, so 'original' vs. 'curator' no longer distinguishes anything, and
-- no Go or Dart code reads or writes this column (docs/GAPS.md).

ALTER TABLE users DROP CONSTRAINT users_creator_type_requires_creator_check;
ALTER TABLE users DROP CONSTRAINT users_creator_type_check;
ALTER TABLE users DROP COLUMN creator_type;
