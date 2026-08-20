import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../app.dart' show routeObserver;
import '../../theme/colors.dart';
import '../auth/auth_controller.dart';
import '../japa/japa_screen.dart';
import '../moderation/moderation_queue_screen.dart';
import '../moderation/report_reel_sheet.dart';
import '../onboarding/save_practice_screen.dart';
import 'data/reel.dart';
import 'data/reel_category.dart';
import 'upload/upload_reel_provider.dart';
import 'upload/upload_reel_screen.dart';

/// The first feed slice (docs/PRD.md §4.1, §7.1): a vertical, full-screen,
/// reverse-chronological feed of already-moderated reels, filterable by
/// category, with no ranking — GET /v1/reels already returns exactly that
/// order, this screen just displays it page by page rather than
/// re-sorting or scoring anything client-side.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> with RouteAware {
  final _pageController = PageController();
  final List<Reel> _reels = [];
  String? _category;
  String? _nextCursor;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;
  int _currentIndex = 0;

  /// False while another route (the japa screen, the upload screen) is
  /// covering this one — see didPushNext/didPopNext. Combined with
  /// [_currentIndex] to decide which _ReelPage, if any, is actually
  /// allowed to play: a reel should never keep making sound behind a
  /// screen meant for eyes-closed, screen-off chanting.
  bool _routeVisible = true;

  /// Global, not per-reel — matches how the mute state on TikTok/Reels-
  /// style feeds persists as you scroll rather than resetting per video.
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _loadPage(reset: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    // Something (the japa screen, the upload screen) was just pushed on
    // top of this one — the currently playing reel, if any, must stop
    // making sound right now, not just visually disappear.
    setState(() => _routeVisible = false);
  }

  @override
  void didPopNext() {
    // Back on top again after whatever covered this screen was popped —
    // resume wherever playback left off.
    setState(() => _routeVisible = true);
  }

  Future<void> _loadPage({required bool reset}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final client = ref.read(reelApiClientProvider);
      final page = await client.listFeed(
        category: _category,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _reels.clear();
        _reels.addAll(page.reels);
        _nextCursor = page.nextCursor;
        _loading = false;
        _initialLoadDone = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        // Plain, person-facing copy (docs/FRONTEND_GUIDELINES.md §9).
        _error = "Couldn't load the feed. Check your connection and try again.";
      });
    }
  }

  void _selectCategory(String? category) {
    if (category == _category) return;
    setState(() {
      _category = category;
      _currentIndex = 0;
    });
    _pageController.jumpToPage(0);
    unawaited(_loadPage(reset: true));
  }

  Future<void> _openUpload() async {
    final uploaded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UploadReelScreen()),
    );
    // A freshly uploaded reel starts PENDING (docs/PRD.md §8 — moderation
    // is a later slice) and won't appear here yet even after a reload;
    // this refresh is about picking up *other* newly approved reels since
    // the screen last loaded, not making the just-uploaded one visible.
    if (uploaded ?? false) {
      unawaited(_loadPage(reset: true));
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    if (index >= _reels.length - 2 && _nextCursor != null) {
      unawaited(_loadPage(reset: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    final isCreator = ref.watch(
      authControllerProvider.select((s) => s.isCreator),
    );
    final isModerator = ref.watch(
      authControllerProvider.select((s) => s.isModerator),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Anhad'),
        actions: [
          if (isCreator)
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Upload',
              onPressed: _openUpload,
            ),
          if (isModerator)
            IconButton(
              icon: const Icon(Icons.shield_outlined),
              tooltip: 'Moderation queue',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ModerationQueueScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.self_improvement),
            tooltip: 'Japa',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const JapaScreen()),
            ),
          ),
          // Always one or the other — never both absent — so there's
          // always a way to sign out of an account that's signed in, or
          // save practice from one that isn't, right next to the japa
          // entry point (mirrors japa_screen.dart's own app bar action).
          if (isAuthenticated)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            )
          else
            IconButton(
              tooltip: 'Save your practice',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavePracticeScreen()),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _CategoryFilterRow(
            selected: _category,
            onSelected: _selectCategory,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_initialLoadDone) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _reels.isEmpty) {
      return _MessageState(message: _error!, onRetry: () => _loadPage(reset: true));
    }
    if (_reels.isEmpty) {
      return _MessageState(
        message: _category == null
            ? 'Nothing here yet. Be the first to share something.'
            : 'Nothing in ${reelCategoryLabel(_category!)} yet.',
        onRetry: () => _loadPage(reset: true),
      );
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _reels.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final reel = _reels[index];
        return _ReelPage(
          key: ValueKey(reel.id),
          reel: reel,
          // Only the current page of a visible (not covered-over) feed
          // screen is ever allowed to actually play — see didPushNext's
          // doc for why _routeVisible has to be part of this, not just
          // _currentIndex.
          isActive: index == _currentIndex && _routeVisible,
          muted: _muted,
          onToggleMute: () => setState(() => _muted = !_muted),
          onReport: () => showReportReelSheet(context, ref, reel.id),
        );
      },
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _FilterChipButton(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final category in reelCategories)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _FilterChipButton(
                label: category.label,
                selected: selected == category.slug,
                onTap: () => onSelected(category.slug),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AnhadColors.accentDiya,
        labelStyle: TextStyle(
          color: selected ? AnhadColors.duskBgBase : AnhadColors.duskTextPrimary,
        ),
        backgroundColor: AnhadColors.duskBgSurface,
        side: BorderSide.none,
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({
    super.key,
    required this.reel,
    required this.isActive,
    required this.muted,
    required this.onToggleMute,
    required this.onReport,
  });

  final Reel reel;
  final bool isActive;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onReport;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  // Nullable and fully torn down (not just paused) the moment this page
  // stops being active — a paused-but-still-alive ExoPlayer instance can
  // be resumed by something outside Flutter's control (observed: the japa
  // screen's own screen-off audio session setup regaining audio focus a
  // few seconds after arrival, which un-paused this same player and made
  // a reel audible behind a screen meant for eyes-closed chanting). A
  // disposed player has no audio focus to regain and cannot do that.
  VideoPlayerController? _controller;
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
    controller.initialize().then((_) {
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
      controller.play();
    });
  }

  void _stopController() {
    final controller = _controller;
    _controller = null;
    _ready = false;
    controller?.dispose();
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
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
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
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
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AnhadColors.accentDiya),
            ),
          Positioned(
            left: 16,
            right: 72,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reelCategoryLabel(widget.reel.category),
                  style: const TextStyle(
                    color: AnhadColors.accentDiya,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.reel.caption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.reel.caption!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 76,
            child: _ReportButton(onTap: widget.onReport),
          ),
          Positioned(
            right: 12,
            bottom: 20,
            child: _MuteButton(muted: widget.muted, onTap: widget.onToggleMute),
          ),
        ],
      ),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.muted, required this.onTap});

  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.flag_outlined, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
