import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../japa/japa_session_controller.dart';
import '../japa/mala_ring_painter.dart';
import 'onboarding_sankalp_screen.dart';

/// Screen 2 of the first-run flow (docs/ONBOARDING.md §3): straight into a
/// working counter, no configuration first. Deliberately pared down from
/// the full [JapaScreen] — no undo, no mala-length picker, no screen-off
/// toggle — those are things a returning user reaches for, not a first-time
/// one mid-mala. Shares [japaSessionControllerProvider] with the real japa
/// screen, so this first mala isn't a separate, throwaway demo count: it's
/// the user's actual practice, continuing seamlessly once onboarding ends.
class OnboardingFirstMalaScreen extends ConsumerStatefulWidget {
  const OnboardingFirstMalaScreen({super.key});

  @override
  ConsumerState<OnboardingFirstMalaScreen> createState() =>
      _OnboardingFirstMalaScreenState();
}

class _OnboardingFirstMalaScreenState
    extends ConsumerState<OnboardingFirstMalaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  /// Guards against advancing twice — the round-completion crossing is
  /// detected via a state-change listener, which could in principle fire
  /// again before the navigation lands.
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        weight: 1,
        tween: Tween(begin: 1.0, end: 1.03)
            .chain(CurveTween(curve: Curves.easeInOut)),
      ),
      TweenSequenceItem(
        weight: 1,
        tween: Tween(begin: 1.03, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
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

  /// The completion bell and haptic already fire on their own — see
  /// [JapaSessionController.onCompletion], wired at the provider level —
  /// this only handles the screen transition. A brief hold after the bead
  /// fills before moving on: "this is the emotional peak, don't rush past
  /// it" (docs/ONBOARDING.md §3).
  Future<void> _advanceAfterCompletion() async {
    if (_advancing) return;
    _advancing = true;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingSankalpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    ref.listen<JapaSessionState>(japaSessionControllerProvider,
        (previous, next) {
      if ((previous?.roundsCompleted ?? 0) == 0 && next.roundsCompleted >= 1) {
        unawaited(_advanceAfterCompletion());
      }
    });

    final state = ref.watch(japaSessionControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Semantics(
          button: true,
          label: 'Tap to record a chant',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: SizedBox.expand(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, _) => CustomPaint(
                          size: const Size.square(280),
                          painter: MalaRingPainter(
                            totalBeads: state.malaLength,
                            filledCount: state.tapsInRound,
                            pulseBeadIndex: state.justFilledBeadIndex,
                            pulseScale:
                                reduceMotion ? 1.0 : _pulseAnimation.value,
                            filledColor: AnhadColors.accentDiya,
                            unfilledColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: 32 + MediaQuery.of(context).padding.bottom,
                      left: 24,
                      right: 24,
                    ),
                    child: Text(
                      // Deliberately not mentioning volume keys / screen-off
                      // here — this pared-down first-mala screen has no
                      // toggle to start that session (see the class doc),
                      // so promising it here would describe a control that
                      // doesn't exist on this screen. It's introduced later,
                      // on the real japa screen, where the toggle actually
                      // is.
                      'Tap anywhere to chant.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AnhadColors.duskTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
