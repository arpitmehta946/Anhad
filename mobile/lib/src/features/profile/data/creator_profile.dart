/// A creator profile, as returned by GET /v1/users/{id}/profile
/// (api/internal/server/profile.go's profileJSON) — the destination Sevak
/// (follow, docs/PRD.md §6) previously had none.
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
    required this.viewerIsFollowing,
    this.displayName,
    this.avatarUrl,
    this.bio,
  });

  factory CreatorProfile.fromJson(Map<String, dynamic> json) => CreatorProfile(
        id: json['id'] as String,
        handle: json['handle'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        bio: json['bio'] as String?,
        role: json['role'] as String,
        isModerator: json['is_moderator'] as bool? ?? false,
        isVerifiedArtist: json['is_verified_artist'] as bool? ?? false,
        isMinorPerformerAccount:
            json['is_minor_performer_account'] as bool? ?? false,
        sevakCount: (json['sevak_count'] as num?)?.toInt() ?? 0,
        viewerIsFollowing: json['viewer_is_following'] as bool? ?? false,
      );

  final String id;
  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String role;
  final bool isModerator;
  final bool isVerifiedArtist;
  final bool isMinorPerformerAccount;
  final int sevakCount;
  final bool viewerIsFollowing;

  bool get isCreator => role == 'creator';

  CreatorProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? bio,
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
      sevakCount: sevakCount ?? this.sevakCount,
      viewerIsFollowing: viewerIsFollowing ?? this.viewerIsFollowing,
    );
  }
}
