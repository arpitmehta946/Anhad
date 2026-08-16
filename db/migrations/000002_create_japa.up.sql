-- japa_streaks, japa_sessions (docs/TECH_STACK.md §6)
-- Written from the periodic Redis batch flush, not per-tap (docs/TECH_STACK.md §5).

CREATE TABLE japa_streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    current_streak INT NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
    longest_streak INT NOT NULL DEFAULT 0 CHECK (longest_streak >= 0),
    last_chanted_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER japa_streaks_set_updated_at
    BEFORE UPDATE ON japa_streaks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE japa_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tap_count INT NOT NULL DEFAULT 0 CHECK (tap_count >= 0),
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE INDEX japa_sessions_user_id_started_at_idx
    ON japa_sessions(user_id, started_at DESC);
