-- The three-layer moderation pipeline (docs/PRD.md §8.1): Whisper STT ->
-- LLM devotional-intent classifier -> audio fingerprint match. Runs async
-- after upload; a pass advances straight to 'approved', a failure or an
-- uncertain verdict is never auto-rejected — it lands in the same
-- moderator queue a user report does, via a system-generated row in
-- `reports` (reporter_id NULL), so the mobile queue screen and the
-- dismiss/remove-reel actions built for reporting need no new UI to
-- also handle pipeline holds.

ALTER TABLE reels DROP CONSTRAINT reels_moderation_status_check;
ALTER TABLE reels ADD CONSTRAINT reels_moderation_status_check
    CHECK (moderation_status IN ('pending', 'held', 'approved', 'rejected'));

-- Nullable throughout: an instrumental with no lyrics (docs/GAPS.md's
-- flagged instrumental gap) legitimately has no transcript and no
-- classifier label to give, and isn't itself an error.
ALTER TABLE reels ADD COLUMN moderation_transcript TEXT;
ALTER TABLE reels ADD COLUMN moderation_classifier_label TEXT
    CHECK (moderation_classifier_label IS NULL OR moderation_classifier_label IN ('devotional', 'secular', 'uncertain'));
ALTER TABLE reels ADD COLUMN moderation_classifier_reason TEXT;
ALTER TABLE reels ADD COLUMN moderation_fingerprint_match TEXT;
ALTER TABLE reels ADD COLUMN moderation_pipeline_completed_at TIMESTAMPTZ;

-- A pipeline hold is a system report, not a human one — reporter_id NULL
-- marks that distinction; reportJSON/QueueItem on the Go and Dart sides
-- both treat a null reporter as "flagged by the moderation pipeline."
ALTER TABLE reports ALTER COLUMN reporter_id DROP NOT NULL;

ALTER TABLE reports DROP CONSTRAINT reports_reason_check;
ALTER TABLE reports ADD CONSTRAINT reports_reason_check
    CHECK (reason IN (
        'not_devotional', 'filmi_commercial', 'financial_solicitation',
        'medical_miracle_claim', 'hate_speech', 'other', 'pipeline_uncertain'
    ));

-- The existing UNIQUE(reporter_id, reel_id) doesn't stop the pipeline
-- filing a second system report for the same reel (NULL <> NULL in a
-- unique constraint) if it somehow ran twice — one open pipeline report
-- per reel at a time is enough; a new one is fine once the old one is
-- resolved (status no longer 'open').
CREATE UNIQUE INDEX reports_one_open_pipeline_report_per_reel_idx
    ON reports(reel_id) WHERE reporter_id IS NULL AND status = 'open';
