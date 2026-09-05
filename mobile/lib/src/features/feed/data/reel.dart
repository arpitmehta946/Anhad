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
///
/// The `jugalbandi*` fields back Jugalbandi (remix/duet, docs/PRD.md §7.2).
/// `jugalbandiEnabled` is this reel's own permission — whether *other*
/// people can record a duet against it. `jugalbandiSourceId` and the
/// `jugalbandiSource*` fields are the opposite direction: only set when
/// this reel itself IS a duet result, carrying just enough about the
/// original (its video, caption, creator) to render the side-by-side
/// playback and attribution without a second request.
///
/// The audio-library fields back "use this sound" (docs/PRD.md §7.3).
/// `audioTrackId` is this reel's OWN track — null until the reel clears
/// moderation and its track is published, or if its creator (or a minor
/// performer's own default, docs/PRD.md §4.5) opted it out of the library
/// entirely. `usedAudioTrackId`/`usedAudioTrackCreatorDisplayName` are the
/// opposite direction: only set when this reel itself was built from
/// someone else's track.
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
    required this.jugalbandiEnabled,
    required this.jugalbandiReuseCount,
    this.caption,
    this.creatorDisplayName,
    this.jugalbandiSourceId,
    this.jugalbandiSourceVideoUrl,
    this.jugalbandiSourceCaption,
    this.jugalbandiSourceCreatorId,
    this.jugalbandiSourceCreatorDisplayName,
    this.audioTrackId,
    this.audioTrackReuseCount = 0,
    this.usedAudioTrackId,
    this.usedAudioTrackCreatorId,
    this.usedAudioTrackCreatorDisplayName,
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
        jugalbandiEnabled: json['jugalbandi_enabled'] as bool? ?? true,
        jugalbandiReuseCount:
            (json['jugalbandi_reuse_count'] as num?)?.toInt() ?? 0,
        jugalbandiSourceId: json['jugalbandi_source_id'] as String?,
        jugalbandiSourceVideoUrl:
            json['jugalbandi_source_video_url'] as String?,
        jugalbandiSourceCaption: json['jugalbandi_source_caption'] as String?,
        jugalbandiSourceCreatorId:
            json['jugalbandi_source_creator_id'] as String?,
        jugalbandiSourceCreatorDisplayName:
            json['jugalbandi_source_creator_display_name'] as String?,
        audioTrackId: json['audio_track_id'] as String?,
        audioTrackReuseCount:
            (json['audio_track_reuse_count'] as num?)?.toInt() ?? 0,
        usedAudioTrackId: json['used_audio_track_id'] as String?,
        usedAudioTrackCreatorId: json['used_audio_track_creator_id'] as String?,
        usedAudioTrackCreatorDisplayName:
            json['used_audio_track_creator_display_name'] as String?,
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
  final bool jugalbandiEnabled;
  final int jugalbandiReuseCount;
  final String? jugalbandiSourceId;
  final String? jugalbandiSourceVideoUrl;
  final String? jugalbandiSourceCaption;
  final String? jugalbandiSourceCreatorId;
  final String? jugalbandiSourceCreatorDisplayName;
  final String? audioTrackId;
  final int audioTrackReuseCount;
  final String? usedAudioTrackId;
  final String? usedAudioTrackCreatorId;
  final String? usedAudioTrackCreatorDisplayName;
  final DateTime createdAt;

  bool get reflectionOnly => commentsMode == 'reflection_only';

  /// True when this reel is itself a Jugalbandi (duet) result — the source
  /// fields are only ever all-present or all-absent together (see this
  /// class's own doc), so checking the id alone is enough.
  bool get isJugalbandi => jugalbandiSourceId != null;

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
      jugalbandiEnabled: jugalbandiEnabled,
      jugalbandiReuseCount: jugalbandiReuseCount,
      jugalbandiSourceId: jugalbandiSourceId,
      jugalbandiSourceVideoUrl: jugalbandiSourceVideoUrl,
      jugalbandiSourceCaption: jugalbandiSourceCaption,
      jugalbandiSourceCreatorId: jugalbandiSourceCreatorId,
      jugalbandiSourceCreatorDisplayName: jugalbandiSourceCreatorDisplayName,
      audioTrackId: audioTrackId,
      audioTrackReuseCount: audioTrackReuseCount,
      usedAudioTrackId: usedAudioTrackId,
      usedAudioTrackCreatorId: usedAudioTrackCreatorId,
      usedAudioTrackCreatorDisplayName: usedAudioTrackCreatorDisplayName,
    );
  }
}
