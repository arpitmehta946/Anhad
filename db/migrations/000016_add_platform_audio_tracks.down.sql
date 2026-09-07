-- Platform tracks are recreatable by re-running cmd/seedaudio against the
-- same source files, unlike real user data — safe to actually delete them
-- here rather than accepting a lossy placeholder the way other down
-- migrations in this file's history do for genuine user-entered data.
DELETE FROM audio_library WHERE is_platform_track;

ALTER TABLE audio_library DROP CONSTRAINT audio_library_platform_ownership_check;
ALTER TABLE audio_library DROP COLUMN is_platform_track;
ALTER TABLE audio_library ALTER COLUMN artist_id SET NOT NULL;
