import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../theme/anhad_icons.dart';
import '../../theme/colors.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_error.dart';
import '../profile/creator_profile_screen.dart';
import 'data/reel.dart';
import 'data/reel_category.dart';
import 'interaction_rail.dart';
import 'satsang_sheet.dart';
import 'social_provider.dart';

/// One full-screen reel: video (or, for a Jugalbandi result, the
/// side-by-side duet view), creator identity, attribution, and the
/// interaction rail. Extracted out of feed_screen.dart's own PageView so a
/// single reel opened from a creator profile's grid (docs/PRD.md's Sevak
/// destination) plays through the exact same widget the main feed uses,
/// rather than a second, inevitably-drifting copy of this rendering logic.
class ReelPage extends StatefulWidget {
  const ReelPage({
    super.key,
    required this.reel,
    required this.isActive,
    required this.muted,
    required this.onToggleMute,
    required this.onReport,
    required this.onReelChanged,
  });

  final Reel reel;
  final bool isActive;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onReport;
  final ValueChanged<Reel> onReelChanged;

  @override
  State<ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<ReelPage> {
  // Nullable and fully torn down (not just paused) the moment this page
  // stops being active — a paused-but-still-alive ExoPlayer instance can
  // be resumed by something outside Flutter's control (observed: the japa
  // screen's own screen-off audio session setup regaining audio focus a
  // few seconds after arrival, which un-paused this same player and made
  // a reel audible behind a screen meant for eyes-closed chanting). A
  // disposed player has no audio focus to regain and cannot do that.
  VideoPlayerController? _controller;
  // Only ever non-null for a Jugalbandi (duet) result — plays the source
  // reel's own video alongside this one (docs/PRD.md §7.2). There's no
  // server-side compositing (JugalbandiRecordScreen's own doc explains
  // why), so the side-by-side view is exactly two independently-loaded
  // players, started/stopped/muted together by this state class.
  VideoPlayerController? _sourceController;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _startController();
  }

  void _startController() {
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.reel.videoUrl))
          ..setLooping(true)
          ..setVolume(widget.muted ? 0 : 1);
    _controller = controller;

    final sourceUrl = widget.reel.jugalbandiSourceVideoUrl;
    VideoPlayerController? sourceController;
    if (sourceUrl != null) {
      sourceController = VideoPlayerController.networkUrl(Uri.parse(sourceUrl))
        ..setLooping(true)
        ..setVolume(widget.muted ? 0 : 1);
      _sourceController = sourceController;
    }

    Future.wait([
      controller.initialize(),
      if (sourceController != null) sourceController.initialize(),
    ]).then((_) {
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
      controller.play();
      sourceController?.play();
    });
  }

  void _stopController() {
    final controller = _controller;
    final sourceController = _sourceController;
    _controller = null;
    _sourceController = null;
    _ready = false;
    controller?.dispose();
    sourceController?.dispose();
  }

  @override
  void didUpdateWidget(covariant ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        setState(_startController);
      } else {
        setState(_stopController);
      }
      return;
    }
    if (widget.muted != oldWidget.muted) {
      _controller?.setVolume(widget.muted ? 0 : 1);
      _sourceController?.setVolume(widget.muted ? 0 : 1);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _sourceController?.dispose();
    super.dispose();
  }

  Future<void> _openSatsangFromCaption(
      BuildContext context, WidgetRef ref) async {
    final freshCount = await showSatsangSheet(context, ref, widget.reel);
    if (freshCount != null) {
      widget.onReelChanged(widget.reel.copyWith(satsangCount: freshCount));
    }
  }

  void _openProfile(BuildContext context, String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreatorProfileScreen(userId: userId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // The system nav/gesture bar sits on top of this full-bleed Stack, not
    // inside a Scaffold body SafeArea already accounts for — without this,
    // the creator name, category, caption, and the bottom of the action
    // rail render underneath it (same class of bug report_reel_sheet.dart
    // had with the keyboard/nav-bar inset). Only the bottom inset is ever
    // non-zero here: the top is already clear of the status bar because
    // the feed's own AppBar and category row push this Stack down.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return GestureDetector(
      onTap: () {
        if (controller == null || !_ready) return;
        setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          if (controller != null && _ready)
            _sourceController != null
                // Jugalbandi (duet) — side by side, source on the left,
                // this performer's own recording on the right, matching
                // the layout instruction directly ("Instagram's duet").
                ? Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _sourceController!.value.aspectRatio,
                            child: VideoPlayer(_sourceController!),
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.white24),
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  )
          else
            const Center(
              child: CircularProgressIndicator(color: AnhadColors.accentDiya),
            ),
          // Instagram/Reels layout: creator identity + caption anchored
          // bottom-left, the action rail bottom-right, full-bleed video
          // behind both (docs/FRONTEND_GUIDELINES.md §4) — a familiar,
          // already-solved arrangement, so viewers don't have to relearn
          // where anything lives just because the icons are Anhad's own.
          Positioned(
            left: 16,
            right: 96,
            bottom: 24 + safeBottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _SevakRow(
                    reel: widget.reel, onReelChanged: widget.onReelChanged),
                // Attribution for both creators (docs/PRD.md §7.2) — the
                // performer is already the reel's own creator, credited
                // above by _SevakRow; this line credits the other half of
                // the duet, the source reel's own creator. Tapping either
                // name opens that person's profile (docs/PRD.md's Sevak
                // destination).
                if (widget.reel.isJugalbandi) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: widget.reel.jugalbandiSourceCreatorId == null
                        ? null
                        : () => _openProfile(
                            context, widget.reel.jugalbandiSourceCreatorId!),
                    child: Text(
                      'Jugalbandi with '
                      '${widget.reel.jugalbandiSourceCreatorDisplayName ?? 'a fellow devotee'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                // Attribution for a reel built via "use this sound"
                // (docs/PRD.md §7.3) — the original track's own creator,
                // distinct from this reel's own performer credited above.
                if (widget.reel.usedAudioTrackId != null) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: widget.reel.usedAudioTrackCreatorId == null
                        ? null
                        : () => _openProfile(
                            context, widget.reel.usedAudioTrackCreatorId!),
                    child: Text(
                      'Audio by '
                      '${widget.reel.usedAudioTrackCreatorDisplayName ?? 'a fellow devotee'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  reelCategoryLabel(widget.reel.category),
                  style: const TextStyle(
                    color: AnhadColors.accentDiya,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.reel.caption != null) ...[
                  const SizedBox(height: 4),
                  // Tapping the caption also opens Satsang, same as the
                  // Satsang icon in the rail — Instagram's own pattern for
                  // the caption/comments relationship, and one less small
                  // target to have to aim for on a full-bleed video.
                  Consumer(
                    builder: (context, ref, _) => GestureDetector(
                      onTap: () => _openSatsangFromCaption(context, ref),
                      child: Text(
                        widget.reel.caption!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 4,
            bottom: 12 + safeBottom,
            child: InteractionRail(
              reel: widget.reel,
              onReelChanged: widget.onReelChanged,
              muted: widget.muted,
              onToggleMute: widget.onToggleMute,
              onReport: widget.onReport,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sevak (Follow, docs/PRD.md §6) — "joining a creator's circle," so it
/// sits with the creator's own name rather than in the reel-scoped
/// InteractionRail alongside Pranam/Satsang/Prasad/Smaran. Tapping the
/// name itself opens that creator's profile (docs/PRD.md's Sevak
/// destination) — a separate tap target from the follow toggle beside it.
class _SevakRow extends ConsumerStatefulWidget {
  const _SevakRow({required this.reel, required this.onReelChanged});

  final Reel reel;
  final ValueChanged<Reel> onReelChanged;

  @override
  ConsumerState<_SevakRow> createState() => _SevakRowState();
}

class _SevakRowState extends ConsumerState<_SevakRow> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final active = await ref
          .read(socialApiClientProvider)
          .toggleSevak(widget.reel.creatorId);
      if (!mounted) return;
      widget
          .onReelChanged(widget.reel.copyWith(viewerFollowingCreator: active));
    } catch (e) {
      if (!mounted) return;
      showAuthAwareSnackBar(context, e, "Couldn't complete that. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatorProfileScreen(userId: widget.reel.creatorId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final following = widget.reel.viewerFollowingCreator;
    final myUserId = ref.watch(authControllerProvider.select((s) => s.userId));
    final isOwnReel = myUserId != null && myUserId == widget.reel.creatorId;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: _openProfile,
            child: Text(
              widget.reel.creatorDisplayName ?? 'A fellow devotee',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // A creator viewing their own reel gets no Sevak control at all —
        // ErrCannotFollowSelf would just reject it server-side anyway, so
        // there's nothing useful to show here.
        if (!isOwnReel)
          Semantics(
            button: true,
            label: following ? 'Unfollow this creator' : 'Follow this creator',
            child: GestureDetector(
              onTap: _busy ? null : _toggle,
              child: Opacity(
                opacity: _busy ? 0.5 : 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SevakIcon(
                      filled: following,
                      color: following ? AnhadColors.accentDiya : Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      following ? 'Following' : 'Follow',
                      style: TextStyle(
                        color:
                            following ? AnhadColors.accentDiya : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
