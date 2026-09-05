/// A creator profile, as returned by GET /v1/users/{id}/profile
/// (api/internal/server/profile.go's profileJSON) — the destination Sevak
/// (follow, docs/PRD.md §6) previously had none.
///
/// [totalReuseCount] — how many times this creator's own audio has been
/// reused across other people's reels ("use this sound," docs/PRD.md §7.3)
/// — is deliberately this profile's headline number, ahead of
/// [sevakCount]: it's a truer read of a devotional singer's actual reach
/// than a follower count, and it's literally the input to the future
/// royalty engine (docs/PRD.md §10.4), so showing it prominently shows a
/// creator the number their earnings will someday be based on.
///
/// [tradition]/[lineage]/[languages]/[instruments] (all optional — a
/// creator who hasn't filled them in just has null/empty values, not an
/// error) are identity fields, not verification claims: unlike
/// [isVerifiedArtist], nothing about them is gated or fact-checked.
///
/// [isMinorPerformerAccount] doesn't hide anything in this model itself —
/// there's no location/school/city field here to hide in the first place
/// (docs/PRD.md §4.5's restriction is automatically satisfied by those
/// fields never having been built, not by this class filtering them out).
/// The UI still reads this flag to decide what *not* to offer (e.g. no
/// direct-message entry point — not built for anyone yet either, but this
/// is the flag that would gate it if it were).
class CreatorProfile {
  const CreatorProfile({
    required this.id,
    required this.handle,
    required this.role,
    required this.isModerator,
    required this.isVerifiedArtist,
    required this.isMinorPerformerAccount,
    required this.sevakCount,
    required this.totalReuseCount,
    required this.viewerIsFollowing,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.tradition,
    this.lineage,
    this.languages = const [],
    this.instruments = const [],
  });

  factory CreatorProfile.fromJson(Map<String, dynamic> json) => CreatorProfile(
        id: json['id'] as String,
        handle: json['handle'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        bio: json['bio'] as String?,
        tradition: json['tradition'] as String?,
        lineage: json['lineage'] as String?,
        languages: (json['languages'] as List?)?.cast<String>() ?? const [],
        instruments: (json['instruments'] as List?)?.cast<String>() ?? const [],
        role: json['role'] as String,
        isModerator: json['is_moderator'] as bool? ?? false,
        isVerifiedArtist: json['is_verified_artist'] as bool? ?? false,
        isMinorPerformerAccount:
            json['is_minor_performer_account'] as bool? ?? false,
        sevakCount: (json['sevak_count'] as num?)?.toInt() ?? 0,
        totalReuseCount: (json['total_reuse_count'] as num?)?.toInt() ?? 0,
        viewerIsFollowing: json['viewer_is_following'] as bool? ?? false,
      );

  final String id;
  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? tradition;
  final String? lineage;
  final List<String> languages;
  final List<String> instruments;
  final String role;
  final bool isModerator;
  final bool isVerifiedArtist;
  final bool isMinorPerformerAccount;
  final int sevakCount;
  final int totalReuseCount;
  final bool viewerIsFollowing;

  bool get isCreator => role == 'creator';

  bool get hasIdentityDetails =>
      (tradition != null && tradition!.isNotEmpty) ||
      (lineage != null && lineage!.isNotEmpty) ||
      languages.isNotEmpty ||
      instruments.isNotEmpty;

  CreatorProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? tradition,
    String? lineage,
    List<String>? languages,
    List<String>? instruments,
    int? sevakCount,
    bool? viewerIsFollowing,
  }) {
    return CreatorProfile(
      id: id,
      handle: handle,
      role: role,
      isModerator: isModerator,
      isVerifiedArtist: isVerifiedArtist,
      isMinorPerformerAccount: isMinorPerformerAccount,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      tradition: tradition ?? this.tradition,
      lineage: lineage ?? this.lineage,
      languages: languages ?? this.languages,
      instruments: instruments ?? this.instruments,
      sevakCount: sevakCount ?? this.sevakCount,
      totalReuseCount: totalReuseCount,
      viewerIsFollowing: viewerIsFollowing ?? this.viewerIsFollowing,
    );
  }
}
