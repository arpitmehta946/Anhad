-- Roles & permissions schema (docs/GAPS.md "Roles & permissions" section).
-- Splits role, status, and permission flags into separate columns instead
-- of one enum trying to do every job — see docs/GAPS.md for the rejected
-- alternatives and why.

ALTER TABLE users ADD COLUMN creator_type TEXT;

UPDATE users SET creator_type = 'original' WHERE role = 'verified_artist';
UPDATE users SET creator_type = 'curator' WHERE role = 'curator';

UPDATE users SET role = 'creator' WHERE role IN ('verified_artist', 'curator');
UPDATE users SET role = 'viewer' WHERE role = 'seeker';

ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ALTER COLUMN role SET DEFAULT 'viewer';
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('viewer', 'creator', 'admin'));

ALTER TABLE users ADD CONSTRAINT users_creator_type_check
    CHECK (creator_type IS NULL OR creator_type IN ('original', 'curator'));
ALTER TABLE users ADD CONSTRAINT users_creator_type_requires_creator_check
    CHECK (creator_type IS NULL OR role = 'creator');

ALTER TABLE users ADD COLUMN status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'pending', 'suspended', 'banned'));

ALTER TABLE users ADD COLUMN is_moderator BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN is_founding_creator BOOLEAN NOT NULL DEFAULT false;
