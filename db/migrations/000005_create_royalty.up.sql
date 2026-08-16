-- artist_wallets, royalty_distributions (docs/TECH_STACK.md §6)

CREATE TABLE artist_wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    artist_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    balance_paise BIGINT NOT NULL DEFAULT 0 CHECK (balance_paise >= 0),
    upi_id TEXT,
    payout_provider TEXT
        CHECK (payout_provider IN ('razorpayx', 'cashfree', 'stripe_connect')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER artist_wallets_set_updated_at
    BEFORE UPDATE ON artist_wallets
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE royalty_distributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    artist_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    audio_id UUID REFERENCES audio_library(id) ON DELETE RESTRICT,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    -- Always a share of the monthly pool (30% of net platform revenue,
    -- docs/PRD.md §10.4) — never a fixed per-play rate, so there is
    -- deliberately no per-play amount column anywhere in this schema.
    amount_paise BIGINT NOT NULL CHECK (amount_paise >= 0),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'paid', 'failed')),
    payout_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (period_end >= period_start)
);

CREATE INDEX royalty_distributions_artist_id_idx ON royalty_distributions(artist_id);
CREATE INDEX royalty_distributions_period_idx ON royalty_distributions(period_start, period_end);

CREATE TRIGGER royalty_distributions_set_updated_at
    BEFORE UPDATE ON royalty_distributions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
