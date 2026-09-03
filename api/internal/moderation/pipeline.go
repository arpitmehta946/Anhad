package moderation

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/anhad/api/internal/store"
)

// PipelineResult is everything one run of the three layers produced,
// independent of what the eval harness or the worker then does with it —
// shared so cmd/moderationeval can run the exact same code path the
// background worker does, not a parallel reimplementation that could
// silently drift from it.
type PipelineResult struct {
	Transcript         string
	Language           string
	ClassifierLabel    ClassifierLabel
	ClassifierReason   string
	FingerprintMatched bool
	FingerprintTrack   string
	// Status is the pipeline's final call: "approved" or "held" — never
	// "rejected". docs/PRD.md's own instruction is that failures and
	// uncertain cases go to the moderator queue, not straight to
	// rejection; only a human moderator action ever produces "rejected"
	// (internal/moderation.Service.RemoveReel).
	Status string
	// HoldReason is set iff Status == "held" — becomes the system
	// report's detail text a moderator sees in the queue.
	HoldReason string
}

// Pipeline wires the three layers together with one policy decision on
// top: docs/PRD.md §8.1's flow is "layer 3 auto-flags known filmi/pop
// tracks," and a fingerprint match is treated as decisive regardless of
// what the classifier thought of the lyrics — this is exactly the
// "devotional-themed Bollywood" hard case your test set names: lyrics
// alone can read as devotional while the track is still a commercial
// recording under someone else's rights, which is what the rights rule
// (PRD.md §4.2.1) and this layer both exist to catch.
type Pipeline struct {
	FFmpegPath  string
	Transcriber Transcriber
	Classifier  IntentClassifier
	Fingerprint FingerprintChecker
	Logger      *slog.Logger
}

// Run executes all three layers against videoURL and returns the
// decision, without touching the database — RunAndSave (pipeline_db.go)
// is the version that also persists the result and updates reel/report
// state, used by the real worker. Kept separate so cmd/moderationeval can
// call Run directly against a local test file with no reels row, no
// store, and no worker involved at all.
func (p *Pipeline) Run(ctx context.Context, videoPath string) (*PipelineResult, error) {
	wavPath, err := ExtractAudio(ctx, p.FFmpegPath, videoPath)
	if err != nil {
		return nil, fmt.Errorf("extract audio: %w", err)
	}
	defer os.Remove(wavPath)

	transcript, err := p.Transcriber.Transcribe(ctx, wavPath)
	if err != nil {
		return nil, fmt.Errorf("transcribe: %w", err)
	}

	verdict, err := p.Classifier.Classify(ctx, transcript.Text)
	if err != nil {
		return nil, fmt.Errorf("classify: %w", err)
	}

	fp, err := p.Fingerprint.Check(ctx, wavPath)
	if err != nil {
		return nil, fmt.Errorf("fingerprint check: %w", err)
	}

	result := &PipelineResult{
		Transcript:         transcript.Text,
		Language:           transcript.Language,
		ClassifierLabel:    verdict.Label,
		ClassifierReason:   verdict.Reason,
		FingerprintMatched: fp.Matched,
		FingerprintTrack:   fp.Track,
	}

	switch {
	case fp.Matched:
		result.Status = "held"
		result.HoldReason = fmt.Sprintf(
			"audio fingerprint matched a known commercial recording (%s) — lyrics alone don't override a rights match",
			fp.Track,
		)
	case verdict.Label == LabelDevotional:
		result.Status = "approved"
	default: // secular or uncertain
		result.Status = "held"
		result.HoldReason = verdict.Reason
	}

	return result, nil
}

// RunAndSave is what the async worker calls: run the pipeline against a
// reel's own video, then persist the result — either straight to
// 'approved', or to 'held' plus a system-generated report (reporter_id
// NULL) so the reel shows up in the moderator queue that reporting
// already built, with no new UI needed to review it. An approved reel's
// audio is then published to the library (docs/PRD.md §7.3) via audioLib —
// never for a held one, matching the "nothing unmoderated is reusable"
// rule this whole package already enforces for the video feed itself.
func RunAndSave(ctx context.Context, st *store.Store, pipeline *Pipeline, audioLib AudioLibrary, reelID, videoURL string) error {
	result, err := pipeline.Run(ctx, videoURL)
	if err != nil {
		pipeline.Logger.Error("moderation pipeline failed", "reel_id", reelID, "error", err)
		return err
	}

	// WHERE ... moderation_status = 'pending' guards a race that's
	// extremely unlikely in the normal flow (nothing can act on a reel
	// through this API before the pipeline itself makes it visible in
	// either the feed or the queue) but cheap to close anyway: if this
	// task somehow runs again after a moderator already reviewed the reel
	// (a manual re-enqueue while testing, a slow/retried task), it must
	// never overwrite that human decision.
	const updateQuery = `
		UPDATE reels SET
			moderation_status = $1,
			moderation_transcript = $2,
			moderation_classifier_label = $3,
			moderation_classifier_reason = $4,
			moderation_fingerprint_match = $5,
			moderation_pipeline_completed_at = $6
		WHERE id = $7 AND moderation_status = 'pending'
	`
	var fingerprintMatch *string
	if result.FingerprintMatched {
		fingerprintMatch = &result.FingerprintTrack
	}
	now := time.Now()
	tag, err := st.PG.Exec(ctx, updateQuery,
		result.Status, result.Transcript, string(result.ClassifierLabel), result.ClassifierReason,
		fingerprintMatch, now, reelID,
	)
	if err != nil {
		return fmt.Errorf("save pipeline result: %w", err)
	}
	if tag.RowsAffected() == 0 {
		pipeline.Logger.Warn("moderation pipeline result discarded — reel already reviewed", "reel_id", reelID)
		return nil
	}

	if result.Status != "held" {
		// Best-effort, same reasoning as the enqueue calls in
		// internal/reels.Service: the reel is already durably approved at
		// this point, so a failure here shouldn't turn a successful
		// moderation run into an error — it just leaves this one reel's
		// audio unpublished, self-healing on the next successful run.
		if err := audioLib.PublishTrackForReel(ctx, reelID); err != nil {
			pipeline.Logger.Error("failed to publish audio track", "reel_id", reelID, "error", err)
		}
		return nil
	}

	const reportQuery = `
		INSERT INTO reports (reporter_id, reel_id, reason, detail)
		VALUES (NULL, $1, $2, $3)
		ON CONFLICT DO NOTHING
	`
	if _, err := st.PG.Exec(ctx, reportQuery, reelID, reasonPipelineUncertain, result.HoldReason); err != nil {
		return fmt.Errorf("file system report for held reel: %w", err)
	}
	return nil
}
