-- In-app reporting + moderator audit log (docs/GAPS.md 🔴 "No in-app
-- reporting mechanism" and 🟡 "No admin audit log") — required under IT
-- Rules 2021 (docs/PRD.md §3.4, §9.3) now that users can post content.

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE CASCADE,
    -- docs/PRD.md §8.0.1's two named harms (financial_solicitation,
    -- medical_miracle_claim) plus the other structural checks this
    -- platform relies on (category correctness, the singing-only scope,
    -- Satsang-comment-style hate speech) and a catch-all.
    reason TEXT NOT NULL
        CHECK (reason IN (
            'not_devotional', 'filmi_commercial', 'financial_solicitation',
            'medical_miracle_claim', 'hate_speech', 'other'
        )),
    detail TEXT,
    -- open -> actioned (the reel was removed) or dismissed (reviewed, no
    -- action taken). Never writable by the reporter past creation.
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'actioned', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- One report per (reporter, reel) ever, not just "per open report" —
    -- the cheapest structural brake on one person mass-reporting the same
    -- creator's content repeatedly (docs/PRD.md §12 "sectarian brigading
    -- policy"). A Redis rate limit (internal/moderation) covers the
    -- broader "reporting many different reels fast" shape of the same risk.
    UNIQUE (reporter_id, reel_id)
);

CREATE INDEX reports_reel_id_idx ON reports(reel_id);
-- Backs the moderator queue's "open reports, oldest first" read.
CREATE INDEX reports_open_created_at_idx ON reports(created_at) WHERE status = 'open';

CREATE TRIGGER reports_set_updated_at
    BEFORE UPDATE ON reports
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Every moderator action, on whatever it acted on — deliberately not
-- scoped to reports alone (report_id is nullable) so a future direct
-- moderator action on a reel (not report-triggered) has somewhere to log
-- to without a schema change.
CREATE TABLE moderation_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    moderator_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    report_id UUID REFERENCES reports(id) ON DELETE SET NULL,
    reel_id UUID NOT NULL REFERENCES reels(id) ON DELETE RESTRICT,
    action TEXT NOT NULL CHECK (action IN ('reel_removed', 'report_dismissed')),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX moderation_audit_log_reel_id_idx ON moderation_audit_log(reel_id);
CREATE INDEX moderation_audit_log_moderator_id_idx ON moderation_audit_log(moderator_id);
