-- audio_library (docs/TECH_STACK.md §6): original tracks stored in R2, whose
-- reuse across many reels is what the audio-royalty pool is calculated from.

CREATE TABLE audio_library (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    artist_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title TEXT NOT NULL,
    deity TEXT,
    raga TEXT,
    category TEXT NOT NULL
        CHECK (category IN ('bhajan', 'mantra', 'stuti', 'chalisa', 'aarti', 'discourse')),
    r2_url TEXT NOT NULL,
    duration_seconds INT CHECK (duration_seconds IS NULL OR duration_seconds > 0),
    play_count BIGINT NOT NULL DEFAULT 0 CHECK (play_count >= 0),
    reuse_count BIGINT NOT NULL DEFAULT 0 CHECK (reuse_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX audio_library_artist_id_idx ON audio_library(artist_id);
CREATE INDEX audio_library_category_idx ON audio_library(category);

CREATE TRIGGER audio_library_set_updated_at
    BEFORE UPDATE ON audio_library
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
