import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_screen.dart';
import '../japa/data/isar_provider.dart';
import '../japa/data/japa_preferences_store.dart';
import '../japa/mala_ring_painter.dart';
import 'onboarding_first_mala_screen.dart';
import 'sapta_swara_painter.dart';

/// Screen 1 of the first-run flow (docs/ONBOARDING.md §3): the sapta swara
/// — seven rings, one per swara of Indian classical music, arising in
/// scale order (docs/FRONTEND_GUIDELINES.md, "Sapta Swara") — behind the
/// same breathing Mala Ring used everywhere else in the app. Deliberately
/// not a devotee figure: the seven notes every bhajan and kirtan melody is
/// built from is this app's own idea, not a borrowed one, and "Anhad"
/// itself names the *anahata nada* — the unstruck sound, produced by
/// nothing striking anything — which is why there's no hand, bell, or
/// figure anywhere in this scene, only sound arising on its own.
class OnboardingArrivalScreen extends ConsumerStatefulWidget {
  const OnboardingArrivalScreen({super.key});

  @override
  ConsumerState<OnboardingArrivalScreen> createState() =>
      _OnboardingArrivalScreenState();
}

class _OnboardingArrivalScreenState
    extends ConsumerState<OnboardingArrivalScreen>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final Animation<double> _ringScaleAnimation;
  late final Animation<double> _ringOpacityAnimation;
  late final Animation<double> _glowScaleAnimation;
  late final Animation<double> _glowOpacityAnimation;

  late final AnimationController _collapseController;

  Ticker? _rippleTicker;
  final _elapsedNotifier = ValueNotifier<Duration>(Duration.zero);

  bool _audioChecked = false;
  bool _collapsing = false;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat(reverse: true);
    final breathCurve =
        CurvedAnimation(parent: _breathController, curve: Curves.easeInOut);
    _ringScaleAnimation = Tween(begin: 1.0, end: 1.045).animate(breathCurve);
    _ringOpacityAnimation = Tween(begin: 0.22, end: 0.46).animate(breathCurve);
    _glowScaleAnimation = Tween(begin: 0.94, end: 1.08).animate(breathCurve);
    _glowOpacityAnimation = Tween(begin: 0.55, end: 1.0).animate(breathCurve);

    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
  }

  void _startRippleTicker() {
    if (_rippleTicker != null) return;
    _rippleTicker = createTicker((elapsed) {
      _elapsedNotifier.value = elapsed;
    })..start();
  }

  /// Checked once per screen visit, the first time dependencies resolve
  /// (so [MediaQuery] is available) — starts the ripple clock.
  ///
  /// The sound is intentionally off for now: tried pitching it down and
  /// softening the timbre, it still read as noisy rather than melodious —
  /// better to pause and revisit deliberately than keep iterating blind.
  /// The synthesis and native speaker-forced-playback plumbing
  /// (sapta_swara_audio.dart, SaptaSwaraPlayer.kt,
  /// device_audio_channel.dart) is untouched; re-enabling is: import
  /// `sapta_swara_audio_provider.dart` and `device_audio_channel.dart`
  /// again, then check `DeviceAudioChannel().isSilencedOrVibrate()` and
  /// call `ref.read(saptaSwaraAudioProvider).playSequence()` here as
  /// before.
  Future<void> _checkMotionAndAudio() async {
    if (_audioChecked) return;
    _audioChecked = true;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!reduceMotion) {
      _startRippleTicker();
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _collapseController.dispose();
    _rippleTicker?.dispose();
    _elapsedNotifier.dispose();
    super.dispose();
  }

  /// This screen shows on every app open (not just the first ever one),
  /// so "Begin" routes one of two ways: still mid first-run flow (a
  /// genuine continuation, plain push), or done with it — which now
  /// always means the feed, signed in or not (viewers browse for free;
  /// the japa screen is one tap away from there, not a separate landing
  /// state). This used to also branch on auth state directly, which
  /// raced the auth controller's own async session restore on a fresh
  /// app open — reading isAuthenticated before that resolved silently
  /// saw its not-yet-determined default (false) and sent an already-
  /// signed-in returning user to the japa screen instead of the feed.
  /// Awaiting AuthController.initialized closes that race; routing
  /// everyone to the same place regardless of auth state means it no
  /// longer matters here anyway.
  Future<void> _handleBegin() async {
    if (_collapsing) return;
    setState(() => _collapsing = true);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!reduceMotion) {
      await _collapseController.forward();
    }
    if (!mounted) return;

    await ref.read(authControllerProvider.notifier).initialized;
    if (!mounted) return;

    final isar = ref.read(isarProvider);
    final complete = await isOnboardingComplete(isar);
    if (complete) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FeedScreen()),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingFirstMalaScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    unawaited(_checkMotionAndAudio());

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              Text(
                'Anhad',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(color: AnhadColors.duskTextPrimary),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _breathController,
                    _collapseController,
                  ]),
                  builder: (context, _) {
                    final collapseT = _collapseController.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // The seven ripples — faded and drawn inward as
                        // "Begin" resolves them into the ring below.
                        if (!reduceMotion || collapseT == 0)
                          Opacity(
                            opacity: reduceMotion ? 1.0 : 1.0 - collapseT,
                            child: Transform.scale(
                              scale: 1.0 - (collapseT * 0.35),
                              child: SizedBox.expand(
                                child: ValueListenableBuilder<Duration>(
                                  valueListenable: _elapsedNotifier,
                                  builder: (context, elapsed, _) =>
                                      CustomPaint(
                                    painter: SaptaSwaraPainter(
                                      elapsedMs: elapsed.inMilliseconds,
                                      reduceMotion: reduceMotion,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Golden glow, breathing behind the ring — swells
                        // and brightens with it, never a spotlight.
                        Container(
                          width: 250 *
                              (reduceMotion
                                  ? 1.0
                                  : _glowScaleAnimation.value) *
                              (1.0 + collapseT * 0.25),
                          height: 250 *
                              (reduceMotion
                                  ? 1.0
                                  : _glowScaleAnimation.value) *
                              (1.0 + collapseT * 0.25),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AnhadColors.accentDiya.withValues(
                                  alpha: (reduceMotion
                                          ? 0.8
                                          : _glowOpacityAnimation.value) *
                                      0.20 *
                                      (1.0 + collapseT),
                                ),
                                AnhadColors.accentDiya.withValues(alpha: 0.09),
                                AnhadColors.accentDiya.withValues(alpha: 0.03),
                                AnhadColors.accentDiya.withValues(alpha: 0),
                              ],
                              stops: const [0.0, 0.32, 0.55, 0.72],
                            ),
                          ),
                        ),
                        // The Mala Ring itself — same signature motif used
                        // everywhere else (docs/FRONTEND_GUIDELINES.md §5),
                        // here breathing in gold rather than showing tap
                        // progress. Briefly brightens as the ripples
                        // resolve into it.
                        Transform.scale(
                          scale: (reduceMotion
                                  ? 1.0
                                  : _ringScaleAnimation.value) +
                              collapseT * 0.15,
                          child: CustomPaint(
                            size: const Size.square(120),
                            painter: MalaRingPainter(
                              totalBeads: 108,
                              filledCount: 0,
                              pulseBeadIndex: null,
                              pulseScale: 1.0,
                              filledColor: AnhadColors.accentDiya,
                              unfilledColor: AnhadColors.accentDiya.withValues(
                                alpha: reduceMotion
                                    ? 0.3
                                    : _ringOpacityAnimation.value +
                                        collapseT * 0.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Text(
                'Where voices gather',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _collapsing ? null : _handleBegin,
                  child: const Text('Begin'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No ads, ever.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AnhadColors.duskTextSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
