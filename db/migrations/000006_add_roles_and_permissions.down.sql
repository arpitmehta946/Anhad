ALTER TABLE users DROP COLUMN is_founding_creator;
ALTER TABLE users DROP COLUMN is_moderator;
ALTER TABLE users DROP COLUMN status;

ALTER TABLE users DROP CONSTRAINT users_creator_type_requires_creator_check;
ALTER TABLE users DROP CONSTRAINT users_creator_type_check;

ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ALTER COLUMN role SET DEFAULT 'seeker';

UPDATE users SET role = 'curator' WHERE role = 'creator' AND creator_type = 'curator';
UPDATE users SET role = 'verified_artist' WHERE role = 'creator';
UPDATE users SET role = 'seeker' WHERE role = 'viewer';

ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('seeker', 'verified_artist', 'curator', 'admin'));

ALTER TABLE users DROP COLUMN creator_type;
