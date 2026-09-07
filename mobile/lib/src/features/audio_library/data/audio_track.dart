/// One track from GET /v1/audio-tracks (api/internal/server/audio.go's
/// trackJson) — only ever a public one; the library endpoint filters out
/// anything a creator (or a minor performer's own default, docs/PRD.md
/// §4.5) has opted out, the same way the reel feed filters out anything
/// unmoderated.
///
/// [creatorId]/[creatorDisplayName] are both absent exactly when
/// [isPlatformTrack] is true (migration 000016's own CHECK constraint on
/// the server side keeps these in lockstep) — a seeded track (a tanpura
/// drone, a temple bell, docs/PRD.md §7.3 P0) isn't anyone's performance,
/// so there's no creator to attribute it to at all, not just an unnamed
/// one.
class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.audioUrl,
    required this.category,
    required this.isPlatformTrack,
    required this.reuseCount,
    required this.playCount,
    required this.createdAt,
    this.sourceReelId,
    this.creatorId,
    this.creatorDisplayName,
    this.title,
  });

  factory AudioTrack.fromJson(Map<String, dynamic> json) => AudioTrack(
        id: json['id'] as String,
        sourceReelId: json['source_reel_id'] as String?,
        creatorId: json['creator_id'] as String?,
        creatorDisplayName: json['creator_display_name'] as String?,
        audioUrl: json['audio_url'] as String,
        category: json['category'] as String,
        title: json['title'] as String?,
        isPlatformTrack: json['is_platform_track'] as bool? ?? false,
        reuseCount: (json['reuse_count'] as num?)?.toInt() ?? 0,
        playCount: (json['play_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String? sourceReelId;
  final String? creatorId;
  final String? creatorDisplayName;
  final String audioUrl;
  final String category;
  final String? title;
  final bool isPlatformTrack;
  final int reuseCount;
  final int playCount;
  final DateTime createdAt;
}
