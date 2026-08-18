import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import 'background/background_japa_controller.dart';
import 'background/background_japa_settings.dart';
import 'japa_session_controller.dart';
import 'mala_ring_painter.dart';

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
  }

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

  Future<void> _startScreenOffSession() async {
    final controller = ref.read(backgroundJapaControllerProvider.notifier);

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
    final currentCount = ref.read(japaSessionControllerProvider).tapsInRound;
    await controller.start(currentCount);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(japaSessionControllerProvider);
    final backgroundModeEnabled = ref.watch(backgroundJapaSettingsProvider);
    final backgroundState = ref.watch(backgroundJapaControllerProvider);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Japa'),
        actions: [
          Row(
            children: [
              const Text('Screen-off', style: TextStyle(fontSize: 12)),
              Switch(
                value: backgroundModeEnabled,
                onChanged: (value) => ref
                    .read(backgroundJapaSettingsProvider.notifier)
                    .setEnabled(value),
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
                      Expanded(
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, _) {
                              return CustomPaint(
                                size: Size.square(ringSize),
                                painter: MalaRingPainter(
                                  totalBeads: malaSize,
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
                            Text(
                              '${state.tapsInRound} / $malaSize',
                              style: theme.textTheme.titleMedium,
                            ),
                            if (state.roundsCompleted > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Round ${state.roundsCompleted + 1}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Today: ${state.dailyTotal}',
                              style: theme.textTheme.bodySmall,
                            ),
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
                            if (backgroundModeEnabled) ...[
                              const SizedBox(height: 16),
                              if (!backgroundState.active)
                                OutlinedButton(
                                  onPressed: _startScreenOffSession,
                                  child: const Text('Start screen-off session'),
                                )
                              else
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                                        backgroundState.paused
                                            ? 'Resume'
                                            : 'Pause',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: ref
                                          .read(
                                            backgroundJapaControllerProvider
                                                .notifier,
                                          )
                                          .end,
                                      child: const Text('End session'),
                                    ),
                                  ],
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
