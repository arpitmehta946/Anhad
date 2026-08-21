/// A queue entry as returned by GET /v1/moderation/reports
/// (api/internal/server/moderation.go's listModerationQueueHandler) — a
/// report joined with just enough about the reported reel to review it
/// without a second request.
class QueueItem {
  const QueueItem({
    required this.id,
    required this.reelId,
    required this.reason,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.reelVideoUrl,
    required this.reelCategory,
    this.detail,
    this.reelCaption,
    this.reelModerationTranscript,
    this.reelModerationLabel,
    this.reelModerationReason,
    this.reelModerationFingerprint,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    final reel = json['reel'] as Map<String, dynamic>;
    return QueueItem(
      id: json['id'] as String,
      reelId: json['reel_id'] as String,
      reason: json['reason'] as String,
      detail: json['detail'] as String?,
      status: json['status'] as String,
      // "pipeline" when the moderation pipeline itself filed this (no
      // human reporter — api/internal/server/moderation.go's reportJSON),
      // "report" for an ordinary user report.
      source: json['source'] as String? ?? 'report',
      createdAt: DateTime.parse(json['created_at'] as String),
      reelVideoUrl: reel['video_url'] as String,
      reelCategory: reel['category'] as String,
      reelCaption: reel['caption'] as String?,
      reelModerationTranscript: reel['moderation_transcript'] as String?,
      reelModerationLabel: reel['moderation_classifier_label'] as String?,
      reelModerationReason: reel['moderation_classifier_reason'] as String?,
      reelModerationFingerprint: reel['moderation_fingerprint_match'] as String?,
    );
  }

  final String id;
  final String reelId;
  final String reason;
  final String? detail;
  final String status;
  final String source;
  final DateTime createdAt;
  final String reelVideoUrl;
  final String reelCategory;
  final String? reelCaption;
  final String? reelModerationTranscript;
  final String? reelModerationLabel;
  final String? reelModerationReason;
  final String? reelModerationFingerprint;

  bool get isPipelineFlagged => source == 'pipeline';
}

/// An entry from GET /v1/moderation/audit-log — who acted on what, when,
/// why (docs/GAPS.md's audit-log gap; also an IT Rules 2021 requirement).
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.moderatorId,
    required this.reelId,
    required this.action,
    required this.createdAt,
    this.reportId,
    this.reason,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as String,
        moderatorId: json['moderator_id'] as String,
        reelId: json['reel_id'] as String,
        action: json['action'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        reportId: json['report_id'] as String?,
        reason: json['reason'] as String?,
      );

  final String id;
  final String moderatorId;
  final String reelId;
  final String action;
  final DateTime createdAt;
  final String? reportId;
  final String? reason;
}
