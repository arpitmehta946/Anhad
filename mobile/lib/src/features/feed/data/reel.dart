/// A single reel, as returned by GET /v1/reels (api/internal/server/reels.go's
/// reelJSON) — only ever an already-`approved` one; the feed endpoint
/// filters PENDING/REJECTED out server-side, not something the client
/// needs to check.
///
/// The four `*Count` fields and the three `viewer*` flags back the P0
/// renamed interactions (docs/PRD.md §6): Pranam=like, Satsang=comment,
/// Prasad=share, Smaran=save, Sevak=follow. `viewer*` is only meaningful
/// when the request that fetched this reel carried a bearer token
/// (api/internal/server/auth.go's optionalAuth) — an anonymous fetch always
/// gets `false` back for all three, which reads correctly either way: an
/// anonymous viewer hasn't pranam'd/smaran'd/followed anything either.
class Reel {
  const Reel({
    required this.id,
    required this.creatorId,
    required this.videoUrl,
    required this.category,
    required this.createdAt,
    required this.commentsMode,
    required this.pranamCount,
    required this.satsangCount,
    required this.prasadCount,
    required this.smaranCount,
    required this.viewerPranamed,
    required this.viewerSmaraned,
    required this.viewerFollowingCreator,
    this.caption,
    this.creatorDisplayName,
  });

  factory Reel.fromJson(Map<String, dynamic> json) => Reel(
        id: json['id'] as String,
        creatorId: json['creator_id'] as String,
        creatorDisplayName: json['creator_display_name'] as String?,
        videoUrl: json['video_url'] as String,
        category: json['category'] as String,
        caption: json['caption'] as String?,
        commentsMode: json['comments_mode'] as String? ?? 'reflection_only',
        pranamCount: (json['pranam_count'] as num?)?.toInt() ?? 0,
        satsangCount: (json['satsang_count'] as num?)?.toInt() ?? 0,
        prasadCount: (json['prasad_count'] as num?)?.toInt() ?? 0,
        smaranCount: (json['smaran_count'] as num?)?.toInt() ?? 0,
        viewerPranamed: json['viewer_pranamed'] as bool? ?? false,
        viewerSmaraned: json['viewer_smaraned'] as bool? ?? false,
        viewerFollowingCreator:
            json['viewer_following_creator'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String creatorId;
  final String? creatorDisplayName;
  final String videoUrl;
  final String category;
  final String? caption;
  final String commentsMode;
  final int pranamCount;
  final int satsangCount;
  final int prasadCount;
  final int smaranCount;
  final bool viewerPranamed;
  final bool viewerSmaraned;
  final bool viewerFollowingCreator;
  final DateTime createdAt;

  bool get reflectionOnly => commentsMode == 'reflection_only';

  /// Returns a copy with the locally-known-fresher engagement fields
  /// swapped in — used right after a Pranam/Smaran/Sevak toggle or a
  /// Satsang post so the UI reflects the just-completed action immediately
  /// rather than waiting for the next feed page load to catch up.
  Reel copyWith({
    int? pranamCount,
    int? satsangCount,
    int? prasadCount,
    int? smaranCount,
    bool? viewerPranamed,
    bool? viewerSmaraned,
    bool? viewerFollowingCreator,
  }) {
    return Reel(
      id: id,
      creatorId: creatorId,
      creatorDisplayName: creatorDisplayName,
      videoUrl: videoUrl,
      category: category,
      caption: caption,
      commentsMode: commentsMode,
      createdAt: createdAt,
      pranamCount: pranamCount ?? this.pranamCount,
      satsangCount: satsangCount ?? this.satsangCount,
      prasadCount: prasadCount ?? this.prasadCount,
      smaranCount: smaranCount ?? this.smaranCount,
      viewerPranamed: viewerPranamed ?? this.viewerPranamed,
      viewerSmaraned: viewerSmaraned ?? this.viewerSmaraned,
      viewerFollowingCreator:
          viewerFollowingCreator ?? this.viewerFollowingCreator,
    );
  }
}
