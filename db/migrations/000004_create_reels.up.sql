-- reels (docs/TECH_STACK.md §6). Engagement columns use their functional
-- names (like/comment), not the poetic Pranam/Satsang UI labels — the
-- rename is a display-layer concern only (docs/FRONTEND_GUIDELINES.md §7).

CREATE TABLE reels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    audio_id UUID REFERENCES audio_library(id) ON DELETE RESTRICT,
    video_url TEXT NOT NULL,
    caption TEXT,
    category TEXT NOT NULL
        CHECK (category IN ('bhajan', 'mantra', 'stuti', 'chalisa', 'aarti', 'discourse')),
    -- Async moderation pipeline (docs/PRD.md §8); always starts pending and
    -- is only ever advanced by the moderation workers, never the client.
    moderation_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (moderation_status IN ('pending', 'approved', 'rejected')),
    view_count BIGINT NOT NULL DEFAULT 0 CHECK (view_count >= 0),
    like_count BIGINT NOT NULL DEFAULT 0 CHECK (like_count >= 0),
    comment_count BIGINT NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX reels_creator_id_idx ON reels(creator_id);
CREATE INDEX reels_audio_id_idx ON reels(audio_id);
CREATE INDEX reels_category_created_at_idx
    ON reels(category, created_at DESC) WHERE moderation_status = 'approved';

CREATE TRIGGER reels_set_updated_at
    BEFORE UPDATE ON reels
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
