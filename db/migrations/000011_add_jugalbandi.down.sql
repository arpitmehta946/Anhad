DROP INDEX IF EXISTS reels_jugalbandi_source_id_idx;
ALTER TABLE reels DROP COLUMN IF EXISTS jugalbandi_reuse_count;
ALTER TABLE reels DROP COLUMN IF EXISTS jugalbandi_source_id;
ALTER TABLE reels DROP COLUMN IF EXISTS jugalbandi_enabled;
ALTER TABLE users DROP COLUMN IF EXISTS is_minor_performer_account;
