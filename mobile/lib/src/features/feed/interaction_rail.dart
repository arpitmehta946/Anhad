import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' show Share, ShareResultStatus;

import '../../theme/anhad_icons.dart';
import '../../theme/colors.dart';
import '../auth/auth_error.dart';
import 'data/reel.dart';
import 'data/reel_category.dart';
import 'jugalbandi/jugalbandi_record_screen.dart';
import 'satsang_sheet.dart';
import 'social_provider.dart';
import 'upload/upload_reel_screen.dart';

/// The right-side action rail holding the four reel-scoped P0 renamed
/// interactions (docs/PRD.md §6/§7.2) — Pranam, Satsang, Prasad, Smaran —
/// each a custom icon (docs/FRONTEND_GUIDELINES.md §7) labelled with its
/// poetic name and live count beneath. The label is what makes a shape a
/// first-time viewer has never seen before legible without falling back to
/// a generic heart/bubble/paper-plane icon (which §7 is explicit the custom
/// shapes themselves are meant to avoid) — the screen-reader label stays
/// purely functional ("Like this reel," never "Pranam this reel") so the
/// two never conflict. Report and Mute (not renamed interactions — they're
/// moderation/playback controls, not part of docs/PRD.md §6's vocabulary)
/// stay icon-only in this same rail, so the whole set of per-reel actions
/// lives in one place without every control competing for label space —
/// this mirrors the vertical action-rail convention Reels/Shorts already
/// established (docs/FRONTEND_GUIDELINES.md §4), just with names attached.
class InteractionRail extends ConsumerWidget {
  const InteractionRail({
    super.key,
    required this.reel,
    required this.onReelChanged,
    required this.muted,
    required this.onToggleMute,
    required this.onReport,
  });

  final Reel reel;
  final ValueChanged<Reel> onReelChanged;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          icon: PranamIcon(
              filled: reel.viewerPranamed,
              color: _pranamColor(reel.viewerPranamed),
              size: 26),
          label: 'Pranam',
          count: reel.pranamCount,
          semanticLabel:
              reel.viewerPranamed ? 'Unlike this reel' : 'Like this reel',
          onTap: () => _togglePranam(context, ref),
        ),
        const SizedBox(height: 14),
        _RailButton(
          icon: const SatsangIcon(filled: false, color: Colors.white, size: 24),
          label: 'Satsang',
          count: reel.satsangCount,
          semanticLabel: 'View comments',
          onTap: () => _openSatsang(context, ref),
        ),
        const SizedBox(height: 14),
        _RailButton(
          icon: const PrasadIcon(filled: false, color: Colors.white, size: 24),
          label: 'Prasad',
          count: reel.prasadCount,
          semanticLabel: 'Share this reel',
          onTap: () => _share(context, ref),
        ),
        // Hidden rather than shown-disabled when the source creator has
        // turned Jugalbandi off (docs/PRD.md §4.5/§7.2) — a visible-but-
        // dead button invites "why won't this work," a missing one
        // doesn't.
        if (reel.jugalbandiEnabled) ...[
          const SizedBox(height: 14),
          _RailButton(
            icon: const JugalbandiIcon(color: Colors.white, size: 24),
            label: 'Jugalbandi',
            semanticLabel: 'Record a duet alongside this reel',
            onTap: () => _openJugalbandi(context),
          ),
        ],
        // Hidden rather than shown-disabled when this reel has no public
        // track of its own yet (docs/PRD.md §7.3) — same reasoning as the
        // Jugalbandi button above: not yet approved, or its creator opted
        // it out of the library entirely, and either way there's nothing
        // to reuse yet.
        if (reel.audioTrackId != null) ...[
          const SizedBox(height: 14),
          _RailButton(
            icon: const Icon(Icons.music_note, color: Colors.white, size: 24),
            label: 'Sound',
            count: reel.audioTrackReuseCount,
            semanticLabel: 'Use this sound in a new reel',
            onTap: () => _useThisSound(context),
          ),
        ],
        const SizedBox(height: 14),
        _RailButton(
          icon: SmaranIcon(
              filled: reel.viewerSmaraned,
              color: _smaranColor(reel.viewerSmaraned),
              size: 24),
          label: 'Smaran',
          count: reel.smaranCount,
          semanticLabel:
              reel.viewerSmaraned ? 'Remove from saved' : 'Save this reel',
          onTap: () => _toggleSmaran(context, ref),
        ),
        const SizedBox(height: 18),
        _RailButton(
          icon: const Icon(Icons.flag_outlined, color: Colors.white, size: 22),
          semanticLabel: 'Report this reel',
          onTap: onReport,
        ),
        const SizedBox(height: 14),
        _RailButton(
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white, size: 22),
          semanticLabel: muted ? 'Unmute' : 'Mute',
          onTap: onToggleMute,
        ),
      ],
    );
  }

  Color _pranamColor(bool active) =>
      active ? AnhadColors.accentDiya : Colors.white;
  Color _smaranColor(bool active) =>
      active ? AnhadColors.accentDiya : Colors.white;

  Future<void> _togglePranam(BuildContext context, WidgetRef ref) async {
    try {
      final result =
          await ref.read(socialApiClientProvider).togglePranam(reel.id);
      onReelChanged(reel.copyWith(
          viewerPranamed: result.active, pranamCount: result.count));
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, e);
    }
  }

  Future<void> _toggleSmaran(BuildContext context, WidgetRef ref) async {
    try {
      final result =
          await ref.read(socialApiClientProvider).toggleSmaran(reel.id);
      onReelChanged(reel.copyWith(
          viewerSmaraned: result.active, smaranCount: result.count));
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, e);
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    // Prasad is "distributing something blessed" (docs/PRD.md §6) — a real
    // hand-off to the OS share sheet, not just a backend counter bump. The
    // count only records once the share sheet itself reports a completed
    // share (ShareResultStatus.success) — Android and iOS both report
    // this. Backing out of the sheet (.dismissed) or a platform that can't
    // report an outcome at all (.unavailable) must NOT count: a share
    // count that includes non-shares is worse than no count, since
    // creators read it as real reach.
    final caption = reel.caption;
    final text = caption != null && caption.isNotEmpty
        ? '$caption — a ${reelCategoryLabel(reel.category)} on Anhad\n${reel.videoUrl}'
        : 'A ${reelCategoryLabel(reel.category)} on Anhad\n${reel.videoUrl}';
    try {
      final result = await Share.share(text);
      if (result.status != ShareResultStatus.success) return;
      final count =
          await ref.read(socialApiClientProvider).recordPrasad(reel.id);
      onReelChanged(reel.copyWith(prasadCount: count));
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, e);
    }
  }

  void _openJugalbandi(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => JugalbandiRecordScreen(sourceReel: reel)),
    );
  }

  void _useThisSound(BuildContext context) {
    final trackId = reel.audioTrackId;
    if (trackId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadReelScreen(
          presetAudioTrackId: trackId,
          presetCategory: reel.category,
        ),
      ),
    );
  }

  Future<void> _openSatsang(BuildContext context, WidgetRef ref) async {
    final freshCount = await showSatsangSheet(context, ref, reel);
    if (freshCount != null) {
      onReelChanged(reel.copyWith(satsangCount: freshCount));
    }
  }

  void _showError(BuildContext context, Object e) {
    if (!context.mounted) return;
    showAuthAwareSnackBar(context, e, "Couldn't complete that. Try again.");
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.label,
    this.count,
  });

  final Widget icon;
  final String semanticLabel;
  final VoidCallback onTap;
  // The poetic name shown under the icon (Pranam/Satsang/Prasad/Smaran) —
  // distinct from [semanticLabel], which stays functional for screen
  // readers regardless of whether this is set (docs/FRONTEND_GUIDELINES.md
  // §7). Report/Mute pass null: they're utility controls, not part of the
  // renamed vocabulary, so they stay icon-only.
  final String? label;
  final int? count;

  static const _textShadows = [Shadow(color: Colors.black54, blurRadius: 3)];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (label != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    label!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: _textShadows,
                    ),
                  ),
                ],
                if (count != null && count! > 0) ...[
                  const SizedBox(height: 1),
                  Text(
                    _formatCount(count!),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      shadows: _textShadows,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return '$count';
    if (count < 100000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '${(count / 1000).round()}k';
  }
}
