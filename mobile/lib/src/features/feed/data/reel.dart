/// A single reel, as returned by GET /v1/reels (api/internal/server/reels.go's
/// reelJSON) — only ever an already-`approved` one; the feed endpoint
/// filters PENDING/REJECTED out server-side, not something the client
/// needs to check.
class Reel {
  const Reel({
    required this.id,
    required this.creatorId,
    required this.videoUrl,
    required this.category,
    required this.createdAt,
    this.caption,
  });

  factory Reel.fromJson(Map<String, dynamic> json) => Reel(
        id: json['id'] as String,
        creatorId: json['creator_id'] as String,
        videoUrl: json['video_url'] as String,
        category: json['category'] as String,
        caption: json['caption'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String creatorId;
  final String videoUrl;
  final String category;
  final String? caption;
  final DateTime createdAt;
}
