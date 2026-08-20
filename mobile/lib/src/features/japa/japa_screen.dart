import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../auth/auth_controller.dart';
import '../onboarding/save_practice_screen.dart';
import 'background/background_japa_controller.dart';
import 'data/isar_provider.dart';
import 'data/japa_preferences_store.dart';
import 'japa_session_controller.dart';
import 'japa_streak_controller.dart';
import 'mala_ring_painter.dart';
import 'reminder/sankalp_reminder_provider.dart';

/// The japa (chant) counter screen (docs/FRONTEND_GUIDELINES.md §10): the
/// Mala Ring dominates the screen, the numeric count is secondary, and
/// tapping anywhere counts a tap.
class JapaScreen extends ConsumerStatefulWidget {
  const JapaScreen({super.key});

  @override
  ConsumerState<JapaScreen> createState() => _JapaScreenState();
}

class _JapaScreenState extends ConsumerState<JapaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  /// Guards [_autoStartIfPreferred] so it fires at most once per screen
  /// instance, the moment a session id becomes available — not on every
  /// rebuild after that.
  bool _autoStartChecked = false;

  /// Whether to show the one-time headphone-privacy banner this screen
  /// visit. Set true only if the native side confirms this has never been
  /// shown before (docs/FRONTEND_GUIDELINES.md §9) — an inline, dismissible
  /// banner rather than a modal: this is informational, not a decision the
  /// user has to make before continuing, and a modal for that trains
  /// people to reflexively dismiss everything.
  bool _showHeadphoneHint = false;

  @override
  void initState() {
    super.initState();
    // §6: a soft breathing pulse (scale 1.0 -> 1.03 -> 1.0), 300-500ms
    // ease-in-out — not a sharp snap. Reduced-motion skips this entirely
    // (see _handleTap and the pulseScale passed to the painter below).
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        weight: 1,
        tween:
            Tween(begin: 1.0, end: 1.03).chain(CurveTween(curve: Curves.easeInOut)),
      ),
      TweenSequenceItem(
        weight: 1,
        tween:
            Tween(begin: 1.03, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
      ),
    ]).animate(_pulseController);

    // Checked once per screen open, independent of session state — the
    // suppression that sets this pending could have happened during any
    // earlier screen-off session, not necessarily this one.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeadphoneHint());
  }

  Future<void> _checkHeadphoneHint() async {
    // Already marked shown, natively, the moment this returns true — a
    // screen-off-triggered suppression surfaces here on next open the same
    // way, with no separate notification (FRONTEND_GUIDELINES.md §8 keeps
    // notifications minimal).
    final shouldShow = await ref
        .read(backgroundJapaControllerProvider.notifier)
        .shouldShowHeadphoneHint();
    if (!mounted || !shouldShow) return;
    setState(() => _showHeadphoneHint = true);
  }

  void _dismissHeadphoneHint() => setState(() => _showHeadphoneHint = false);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    HapticFeedback.lightImpact();
    await ref.read(japaSessionControllerProvider.notifier).tap();
    if (!mounted) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!reduceMotion) {
      _pulseController.forward(from: 0);
    }
  }

  /// The one control for the screen-off session — flipping it on runs
  /// through the permission checks (only actually prompting the first
  /// time; both checks reflect real system state, not a "have we asked
  /// before" flag) and starts the session, flipping it off ends it. A
  /// separate persistent-setting toggle plus a separate start button was
  /// two controls narrating one concept — this is the single one, matching
  /// FRONTEND_GUIDELINES.md §9 ("the vocabulary stays identical through a
  /// whole flow").
  Future<void> _toggleScreenOffSession(bool wantsOn) async {
    final controller = ref.read(backgroundJapaControllerProvider.notifier);
    if (!wantsOn) {
      await controller.end();
      return;
    }

    if (!await controller.hasNotificationPermission()) {
      final granted = await controller.requestNotificationPermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification permission is needed to show the live count '
              'while chanting screen-off.',
            ),
          ),
        );
        return;
      }
    }

    if (await controller.needsBatteryExemption()) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep the session running'),
          content: const Text(
            'Android may otherwise stop your chant count a few minutes '
            'after the screen turns off. The next screen lets you exempt '
            'Anhad from battery optimization so it keeps counting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed ?? false) {
        await controller.requestBatteryExemption();
      }
    }
    final japaSessionController = ref.read(japaSessionControllerProvider.notifier);
    final japaState = ref.read(japaSessionControllerProvider);
    final sessionId = japaState.sessionId;
    if (sessionId == null) return;
    await controller.start(
      sessionId: sessionId,
      currentCount: japaSessionController.cumulativeTotal,
      cumulativeBase: japaSessionController.cumulativeBase,
      malaLength: japaState.malaLength,
    );
  }

  /// Corrects an accidental tap. Silent on success (the ring/count/
  /// notification visibly drop by one, which is confirmation enough) —
  /// only speaks up when there was nothing to undo, since a toast on every
  /// successful undo would be noise for the exact moment a user is trying
  /// to fix a mistake quickly.
  Future<void> _undoLastTap() async {
    final undone =
        await ref.read(japaSessionControllerProvider.notifier).undoLastTap();
    if (!mounted || undone) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing to undo')),
    );
  }

  /// The screen-off preference (docs/PRD.md §7.4) is meant to stick: once a
  /// user turns it on, every future app open should engage it automatically
  /// rather than making them flip the toggle again each time. This runs
  /// through the same permission/battery-exemption flow as a manual toggle
  /// so it's held to the same standard, not a silent bypass of it.
  Future<void> _autoStartIfPreferred() async {
    if (ref.read(backgroundJapaControllerProvider).active) return;
    final controller = ref.read(backgroundJapaControllerProvider.notifier);
    final preferred = await controller.isScreenOffPreferred();
    if (!preferred || !mounted) return;
    // Re-check after the await: a notification-driven state change or the
    // user's own tap could have already started (or ended) a session while
    // this was in flight.
    if (ref.read(backgroundJapaControllerProvider).active) return;
    await _toggleScreenOffSession(true);
  }

  /// Pushes the sankalp reminder's single pending occurrence from today to
  /// tomorrow whenever today's locked daily target is already met —
  /// checked against whatever [dailyTotal] currently is, not just a live
  /// crossing within this screen visit, since the target could just as
  /// well have been met by a screen-off session, or before this screen
  /// was even opened today. [rescheduleForTomorrow] is idempotent (it
  /// just moves the one pending occurrence, again, to the same place), so
  /// there's no harm in this running more than once for the same day.
  Future<void> _checkSankalpTargetMet(int dailyTotal) async {
    final isar = ref.read(isarProvider);
    final reminder = await activeSankalpReminder(isar);
    if (reminder == null || dailyTotal < reminder.dailyTarget) return;
    if (!mounted) return;
    await ref.read(sankalpReminderSchedulerProvider).rescheduleForTomorrow(
          TimeOfDay(hour: reminder.reminderHour, minute: reminder.reminderMinute),
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<JapaSessionState>(
      japaSessionControllerProvider,
      (previous, next) {
        if (previous?.dailyTotal == next.dailyTotal) return;
        unawaited(_checkSankalpTargetMet(next.dailyTotal));
      },
    );
    final state = ref.watch(japaSessionControllerProvider);
    final backgroundState = ref.watch(backgroundJapaControllerProvider);
    final streak = ref.watch(japaStreakProvider).valueOrNull;
    final isAuthenticated = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final theme = Theme.of(context);

    if (!_autoStartChecked && state.sessionId != null) {
      _autoStartChecked = true;
      unawaited(_autoStartIfPreferred());
      // ref.listen above only reacts to dailyTotal *changing* — it won't
      // see a target that was already met before this screen opened (a
      // screen-off session, or an earlier visit today). One explicit
      // check against whatever the state already is, gated the same way
      // _autoStartIfPreferred is so it only runs once per screen visit.
      unawaited(_checkSankalpTargetMet(state.dailyTotal));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Japa'),
        actions: [
          // Unauthenticated gets the explanatory banner below instead of an
          // icon-only action here — an icon alone didn't tell a returning,
          // not-yet-signed-in user what it actually did.
          //
          // A signed-in user reaching this screen straight from onboarding
          // (rather than via FeedScreen's own sign-out button) had no way
          // back to one — this is that, regardless of how the screen was
          // reached.
          if (isAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).logout();
                // If this screen was reached by pushing on top of
                // FeedScreen (the only way to see this button — it's
                // authenticated-only), the root now wants to show a plain
                // JapaScreen of its own; drop back to it instead of
                // leaving a second, stale JapaScreen stacked underneath.
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last tap',
            onPressed: _undoLastTap,
          ),
          Row(
            children: [
              const Text('Screen-off japa', style: TextStyle(fontSize: 12)),
              Switch(
                value: backgroundState.active,
                onChanged: _toggleScreenOffSession,
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Semantics(
          button: true,
          label: 'Tap to record a chant',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: SizedBox.expand(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Size the ring off the actual available space rather
                  // than a fixed constant, so it never overflows into (and
                  // gets clipped by) the text below on shorter screens.
                  final ringSize = min(
                    constraints.maxWidth * 0.82,
                    constraints.maxHeight * 0.55,
                  ).clamp(180.0, 380.0);
                  return Column(
                    children: [
                      // Persists (no dismiss) for as long as the state it
                      // describes is true, unlike the one-time headphone
                      // hint below it — this isn't a one-off notice, it's
                      // pointing at a real, ongoing "not saved yet" state,
                      // and disappears on its own the moment that's fixed.
                      if (!isAuthenticated)
                        _SavePracticeBanner(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SavePracticeScreen(),
                            ),
                          ),
                        ),
                      if (_showHeadphoneHint)
                        _HeadphoneHintBanner(onDismiss: _dismissHeadphoneHint),
                      Expanded(
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, _) {
                              return CustomPaint(
                                size: Size.square(ringSize),
                                painter: MalaRingPainter(
                                  totalBeads: state.malaLength,
                                  filledCount: state.tapsInRound,
                                  pulseBeadIndex: state.justFilledBeadIndex,
                                  pulseScale: reduceMotion
                                      ? 1.0
                                      : _pulseAnimation.value,
                                  filledColor: AnhadColors.accentDiya,
                                  unfilledColor: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.22),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: 24 + MediaQuery.of(context).padding.bottom,
                          left: 24,
                          right: 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Today's cumulative count is what a user
                            // actually cares about day to day — the current
                            // round resetting on a fresh screen visit
                            // (japa_session_controller.dart) is technically
                            // correct but reads as lost progress if it's the
                            // prominent number. The Mala Ring itself stays
                            // the dominant visual either way (§10) — this
                            // only reorders the supporting text beneath it.
                            Text(
                              '${state.dailyTotal}',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AnhadColors.accentDiya,
                              ),
                            ),
                            Text(
                              'chants today',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (streak != null && streak.lifetimeTotal > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${streak.lifetimeTotal} lifetime',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              state.roundsCompleted > 0
                                  ? '${state.tapsInRound} / ${state.malaLength}'
                                      ' · Round ${state.roundsCompleted + 1}'
                                  : '${state.tapsInRound} / ${state.malaLength}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                for (final length in malaLengthOptions)
                                  _MalaLengthOption(
                                    length: length,
                                    selected: state.malaLength == length,
                                    onSelected: () => ref
                                        .read(
                                          japaSessionControllerProvider
                                              .notifier,
                                        )
                                        .setMalaLength(length),
                                  ),
                              ],
                            ),
                            // Shown only once there's a streak to report —
                            // silence rather than "no streak yet" for a new
                            // or just-broken streak is the neutral,
                            // non-guilt-tripping option (FRONTEND_GUIDELINES
                            // §8/§9: no "you lost your streak" framing, and
                            // an empty state should read as an invitation,
                            // not an apology).
                            if (streak != null && streak.currentStreak > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${streak.currentStreak}-day streak',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AnhadColors.accentDiya,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              'Tap anywhere to chant',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            if (state.syncFailed) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Not synced yet — check your connection',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AnhadColors.accentSindoor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (backgroundState.active) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: backgroundState.paused
                                    ? ref
                                        .read(
                                          backgroundJapaControllerProvider
                                              .notifier,
                                        )
                                        .resume
                                    : ref
                                        .read(
                                          backgroundJapaControllerProvider
                                              .notifier,
                                        )
                                        .pause,
                                child: Text(
                                  backgroundState.paused ? 'Resume' : 'Pause',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The unauthenticated-state notice — practice is real and counting
/// locally, but nothing survives a reinstall or carries to another device
/// until this is tapped (docs/ONBOARDING.md §7, docs/PRD.md §4.5). Replaces
/// the earlier icon-only app bar action, which told a returning user
/// nothing about what it actually did.
class _SavePracticeBanner extends StatelessWidget {
  const _SavePracticeBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(4),
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: AnhadColors.duskBgSurface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_upload_outlined,
                  color: AnhadColors.accentDiya, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Save your practice',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AnhadColors.duskTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      "So it's here tomorrow, and on any phone you sign "
                      'in from.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AnhadColors.duskTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AnhadColors.duskTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one-time headphone-privacy notice (docs/ONBOARDING.md §5 item 1) —
/// an inline, dismissible banner, not a modal: nothing here needs a
/// decision before the user can continue chanting. Benefit-led copy
/// ("your bell stays private") rather than feature-led ("the sound only
/// plays through headphones"), per the same research FRONTEND_GUIDELINES.md
/// §9 draws on for plain, person-facing language.
class _HeadphoneHintBanner extends StatelessWidget {
  const _HeadphoneHintBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AnhadColors.duskBgSurface,
        // The soft-arched-top-edge chrome motif (FRONTEND_GUIDELINES.md
        // §4), scaled down to a single asymmetric corner for a banner this
        // small rather than a full arch.
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.headphones, color: AnhadColors.accentDiya, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your bell stays private — it plays through headphones only, '
              'never the speaker.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AnhadColors.duskTextPrimary,
                  ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(
              foregroundColor: AnhadColors.accentDiya,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// One choice in the mala-length row (docs/ONBOARDING.md §1.3). A plain
/// labeled toggle rather than a Material ChoiceChip, so it matches the
/// app's existing OutlinedButton/FilledButton vocabulary instead of
/// introducing a different chip aesthetic for one control.
class _MalaLengthOption extends StatelessWidget {
  const _MalaLengthOption({
    required this.length,
    required this.selected,
    required this.onSelected,
  });

  final int length;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final label = Text('$length');
    return SizedBox(
      height: 32,
      child: selected
          ? FilledButton(
              onPressed: onSelected,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: Size.zero,
              ),
              child: label,
            )
          : OutlinedButton(
              onPressed: onSelected,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: Size.zero,
              ),
              child: label,
            ),
    );
  }
}
