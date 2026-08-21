DROP INDEX reports_one_open_pipeline_report_per_reel_idx;

ALTER TABLE reports DROP CONSTRAINT reports_reason_check;
ALTER TABLE reports ADD CONSTRAINT reports_reason_check
    CHECK (reason IN (
        'not_devotional', 'filmi_commercial', 'financial_solicitation',
        'medical_miracle_claim', 'hate_speech', 'other'
    ));

DELETE FROM reports WHERE reporter_id IS NULL;
ALTER TABLE reports ALTER COLUMN reporter_id SET NOT NULL;

ALTER TABLE reels DROP COLUMN moderation_pipeline_completed_at;
ALTER TABLE reels DROP COLUMN moderation_fingerprint_match;
ALTER TABLE reels DROP COLUMN moderation_classifier_reason;
ALTER TABLE reels DROP COLUMN moderation_classifier_label;
ALTER TABLE reels DROP COLUMN moderation_transcript;

UPDATE reels SET moderation_status = 'pending' WHERE moderation_status = 'held';
ALTER TABLE reels DROP CONSTRAINT reels_moderation_status_check;
ALTER TABLE reels ADD CONSTRAINT reels_moderation_status_check
    CHECK (moderation_status IN ('pending', 'approved', 'rejected'));
