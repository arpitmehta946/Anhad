import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../theme/colors.dart';
import '../audio_library/audio_library_provider.dart';
import '../audio_library/data/audio_track.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_error.dart';
import '../feed/data/reel.dart';
import '../feed/data/reel_api_client.dart' show FeedPage;
import '../feed/data/reel_category.dart';
import '../feed/social_provider.dart';
import '../feed/upload/upload_reel_provider.dart';
import '../feed/upload/upload_reel_screen.dart';
import 'data/creator_profile.dart';
import 'edit_profile_screen.dart';
import 'profile_provider.dart';
import 'single_reel_screen.dart';

/// A creator's profile — the destination Sevak (follow, docs/PRD.md §6)
/// previously had none: following someone led nowhere to actually visit.
/// Reached by tapping a creator's name anywhere it appears (the feed, the
/// sound library, Satsang comments, Jugalbandi attribution), or your own,
/// via the feed's own AppBar action.
class CreatorProfileScreen extends ConsumerStatefulWidget {
  const CreatorProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<CreatorProfileScreen> createState() =>
      _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends ConsumerState<CreatorProfileScreen> {
  CreatorProfile? _profile;
  String? _error;
  bool _sevakBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final profile =
          await ref.read(profileApiClientProvider).getProfile(widget.userId);
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeAuthAwareError(
            e, "Couldn't load this profile. Check your connection and try again.");
      });
    }
  }

  Future<void> _toggleSevak() async {
    final profile = _profile;
    if (profile == null || _sevakBusy) return;
    setState(() => _sevakBusy = true);
    try {
      final active =
          await ref.read(socialApiClientProvider).toggleSevak(profile.id);
      if (!mounted) return;
      setState(() {
        _profile = profile.copyWith(
          viewerIsFollowing: active,
          sevakCount: profile.sevakCount + (active ? 1 : -1),
        );
      });
    } catch (e) {
      if (!mounted) return;
      showAuthAwareSnackBar(context, e, "Couldn't complete that. Try again.");
    } finally {
      if (mounted) setState(() => _sevakBusy = false);
    }
  }

  Future<void> _editProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final updated = await Navigator.of(context).push<CreatorProfile>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
    );
    if (updated != null && mounted) setState(() => _profile = updated);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: Text(profile?.displayName ?? 'Profile')),
      body: profile == null
          ? _bodyBeforeLoaded()
          : DefaultTabController(
              length: 3,
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(child: _ProfileHeader(
                    profile: profile,
                    isOwnProfile: _isOwnProfile(),
                    sevakBusy: _sevakBusy,
                    onToggleSevak: _toggleSevak,
                    onEdit: _editProfile,
                  )),
                  const SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(),
                  ),
                ],
                body: TabBarView(
                  children: [
                    _ReelsGrid(
                      fetchPage: ({cursor}) => ref
                          .read(reelApiClientProvider)
                          .listFeed(creatorId: widget.userId, cursor: cursor),
                      emptyMessage: 'No reels yet.',
                      loadErrorMessage:
                          "Couldn't load reels. Check your connection and try again.",
                    ),
                    _SoundsList(userId: widget.userId),
                    // Appears On (docs/PRD.md §7.2, §7.3): other creators'
                    // reels that feature this creator without belonging to
                    // them — a Jugalbandi duet against their reel, or a
                    // reel built from their audio. A Spotify/TIDAL-style
                    // credit list Instagram has no equivalent of.
                    _ReelsGrid(
                      fetchPage: ({cursor}) => ref
                          .read(reelApiClientProvider)
                          .listAppearsOn(widget.userId, cursor: cursor),
                      emptyMessage:
                          'Nothing yet — reels that duet with them or '
                          'reuse their audio will show up here.',
                      loadErrorMessage:
                          "Couldn't load this. Check your connection and try again.",
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  bool _isOwnProfile() {
    final myUserId = ref.read(authControllerProvider.select((s) => s.userId));
    return myUserId != null && myUserId == widget.userId;
  }

  Widget _bodyBeforeLoaded() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AnhadColors.duskTextSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isOwnProfile,
    required this.sevakBusy,
    required this.onToggleSevak,
    required this.onEdit,
  });

  final CreatorProfile profile;
  final bool isOwnProfile;
  final bool sevakBusy;
  final VoidCallback onToggleSevak;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = profile.avatarUrl;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AnhadColors.duskBgSurface,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? const Icon(Icons.person, size: 36)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName ?? 'A fellow devotee',
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // A quiet factual marker, not a stat block
                        // (docs/FRONTEND_GUIDELINES.md §10) — no level, no
                        // XP, just a small check where it's actually true.
                        if (profile.isVerifiedArtist) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle,
                              color: AnhadColors.accentTulsi, size: 18),
                        ],
                      ],
                    ),
                    Text(
                      '@${profile.handle}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AnhadColors.duskTextSecondary),
                    ),
                    const SizedBox(height: 10),
                    // Reuse count leads, Sevak count follows, smaller — a
                    // follower count measures attention; reuse count
                    // measures how many other reels actually carry this
                    // creator's voice, which is both a truer read of a
                    // devotional singer's reach and literally the input to
                    // the future royalty engine (docs/PRD.md §10.4). This
                    // is a plain number, not a stat block with levels or
                    // XP (docs/FRONTEND_GUIDELINES.md §10).
                    RichText(
                      text: TextSpan(
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: AnhadColors.accentDiya,
                            fontWeight: FontWeight.bold),
                        children: [
                          TextSpan(text: '${profile.totalReuseCount}'),
                          TextSpan(
                            text: ' reuse'
                                '${profile.totalReuseCount == 1 ? '' : 's'}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AnhadColors.duskTextSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.sevakCount} Sevak'
                      '${profile.sevakCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AnhadColors.duskTextSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(profile.bio!, style: theme.textTheme.bodyMedium),
          ],
          if (profile.hasIdentityDetails) ...[
            const SizedBox(height: 12),
            _IdentityBlock(profile: profile),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: isOwnProfile
                ? OutlinedButton(
                    onPressed: onEdit, child: const Text('Edit profile'))
                : FilledButton(
                    onPressed: sevakBusy ? null : onToggleSevak,
                    style: profile.viewerIsFollowing
                        ? FilledButton.styleFrom(
                            backgroundColor: AnhadColors.duskBgSurface,
                            foregroundColor: AnhadColors.duskTextPrimary,
                          )
                        : null,
                    child: Text(
                        profile.viewerIsFollowing ? 'Following' : 'Sevak'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The optional identity block — tradition/sampradaya, lineage, languages,
/// instruments (migration 000015) — shown only when at least one is set.
/// Plain labeled text, not badges or chips with implied levels: these are
/// facts about who someone is, not achievements.
class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.profile});

  final CreatorProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <String>[
      if (profile.tradition != null && profile.tradition!.isNotEmpty)
        profile.tradition!,
      if (profile.lineage != null && profile.lineage!.isNotEmpty)
        profile.lineage!,
      if (profile.languages.isNotEmpty) profile.languages.join(', '),
      if (profile.instruments.isNotEmpty) profile.instruments.join(', '),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: rows
          .map((r) => Text(
                r,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ))
          .toList(),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate();

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const TabBar(
        tabs: [
          Tab(text: 'Reels'),
          Tab(text: 'Sounds'),
          Tab(text: 'Appears On'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

/// A grid of reels — deliberately not a video thumbnail grid (no
/// thumbnail-extraction pipeline exists yet, docs/GAPS.md-worthy on its
/// own); each tile shows what's already known about the reel (category,
/// Pranam count) without needing one. Tapping a tile opens the real thing
/// (SingleReelScreen).
///
/// Reused for both the profile's own Reels tab and its Appears On tab —
/// [fetchPage] is the only thing that differs between them
/// (ReelApiClient.listFeed vs .listAppearsOn), so this widget doesn't need
/// to know which one it's showing.
class _ReelsGrid extends ConsumerStatefulWidget {
  const _ReelsGrid({
    required this.fetchPage,
    required this.emptyMessage,
    required this.loadErrorMessage,
  });

  final Future<FeedPage> Function({String? cursor}) fetchPage;
  final String emptyMessage;
  final String loadErrorMessage;

  @override
  ConsumerState<_ReelsGrid> createState() => _ReelsGridState();
}

class _ReelsGridState extends ConsumerState<_ReelsGrid> {
  final List<Reel> _reels = [];
  String? _nextCursor;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page =
          await widget.fetchPage(cursor: reset ? null : _nextCursor);
      if (!mounted) return;
      setState(() {
        if (reset) _reels.clear();
        _reels.addAll(page.reels);
        _nextCursor = page.nextCursor;
        _loading = false;
        _loaded = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loaded = true;
        _error = widget.loadErrorMessage;
      });
    }
  }

  void _openReel(Reel reel) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SingleReelScreen(reel: reel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_error != null && _reels.isEmpty) {
      return _EmptyState(message: _error!, onRetry: () => _load(reset: true));
    }
    if (_reels.isEmpty) {
      return _EmptyState(message: widget.emptyMessage);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300 && _nextCursor != null) {
          unawaited(_load(reset: false));
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 9 / 16,
        ),
        itemCount: _reels.length,
        itemBuilder: (context, index) {
          final reel = _reels[index];
          return GestureDetector(
            onTap: () => _openReel(reel),
            child: Container(
              color: AnhadColors.duskBgSurface,
              child: Stack(
                children: [
                  const Center(
                    child: Icon(Icons.play_arrow,
                        color: AnhadColors.duskTextSecondary, size: 28),
                  ),
                  Positioned(
                    left: 4,
                    right: 4,
                    top: 4,
                    child: Text(
                      reelCategoryLabel(reel.category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AnhadColors.accentDiya, fontSize: 10),
                    ),
                  ),
                  if (reel.pranamCount > 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Text(
                        '${reel.pranamCount}',
                        style: const TextStyle(
                            color: AnhadColors.duskTextSecondary,
                            fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A creator's own tracks in the sound library (docs/PRD.md §7.3), with
/// reuse counts — a minor performer's excluded tracks simply never appear
/// here, since the underlying listing already only ever returns public
/// ones (docs/PRD.md §4.5), the same filter the main library screen relies
/// on.
class _SoundsList extends ConsumerStatefulWidget {
  const _SoundsList({required this.userId});

  final String userId;

  @override
  ConsumerState<_SoundsList> createState() => _SoundsListState();
}

class _SoundsListState extends ConsumerState<_SoundsList> {
  final List<AudioTrack> _tracks = [];
  String? _nextCursor;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  final _player = AudioPlayer();
  String? _playingTrackId;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(audioLibraryApiClientProvider).listLibrary(
            creatorId: widget.userId,
            cursor: reset ? null : _nextCursor,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _tracks.clear();
        _tracks.addAll(page.tracks);
        _nextCursor = page.nextCursor;
        _loading = false;
        _loaded = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loaded = true;
        _error = "Couldn't load sounds. Check your connection and try again.";
      });
    }
  }

  Future<void> _togglePreview(AudioTrack track) async {
    if (_playingTrackId == track.id) {
      await _player.stop();
      setState(() => _playingTrackId = null);
      return;
    }
    try {
      await _player.setUrl(track.audioUrl);
      unawaited(_player.play());
      setState(() => _playingTrackId = track.id);
      unawaited(
          ref.read(audioLibraryApiClientProvider).recordPlay(track.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't play this track.")),
      );
    }
  }

  void _useSound(AudioTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadReelScreen(
          presetAudioTrackId: track.id,
          presetCategory: track.category,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_error != null && _tracks.isEmpty) {
      return _EmptyState(message: _error!, onRetry: () => _load(reset: true));
    }
    if (_tracks.isEmpty) {
      return const _EmptyState(message: 'No sounds in the library yet.');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300 && _nextCursor != null) {
          unawaited(_load(reset: false));
        }
        return false;
      },
      child: ListView.separated(
        itemCount: _tracks.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final track = _tracks[index];
          final playing = _playingTrackId == track.id;
          return ListTile(
            leading: IconButton(
              icon: Icon(
                  playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
              color: AnhadColors.accentDiya,
              onPressed: () => _togglePreview(track),
            ),
            title: Text(track.title ?? reelCategoryLabel(track.category)),
            subtitle: Text(
              'used in ${track.reuseCount} reel${track.reuseCount == 1 ? '' : 's'}'
              ' · ${track.playCount} play${track.playCount == 1 ? '' : 's'}',
            ),
            trailing: TextButton(
              onPressed: () => _useSound(track),
              child: const Text('Use'),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AnhadColors.duskTextSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
