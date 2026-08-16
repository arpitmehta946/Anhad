-- users, user_subscriptions (docs/TECH_STACK.md §6)

CREATE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number TEXT NOT NULL UNIQUE,
    display_name TEXT,
    avatar_url TEXT,
    role TEXT NOT NULL DEFAULT 'seeker'
        CHECK (role IN ('seeker', 'verified_artist', 'curator', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE user_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan TEXT NOT NULL CHECK (plan IN ('seva_pass', 'creator_studio_pro')),
    status TEXT NOT NULL DEFAULT 'trialing'
        CHECK (status IN ('trialing', 'active', 'canceled', 'expired')),
    -- 'streak_reward' is the 21-day-streak trial unlock (docs/PRD.md §10.3).
    -- It must never become a permanent unlock, hence the trial_ends_at
    -- constraint below capping it at 7 days from creation.
    source TEXT NOT NULL DEFAULT 'purchase'
        CHECK (source IN ('purchase', 'streak_reward')),
    trial_ends_at TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    razorpay_subscription_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        source != 'streak_reward'
        OR (trial_ends_at IS NOT NULL AND trial_ends_at <= created_at + INTERVAL '7 days')
    )
);

CREATE INDEX user_subscriptions_user_id_idx ON user_subscriptions(user_id);

CREATE TRIGGER user_subscriptions_set_updated_at
    BEFORE UPDATE ON user_subscriptions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
