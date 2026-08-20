import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_screen.dart';
import '../japa/data/isar_provider.dart';
import '../japa/data/japa_preferences_store.dart';
import '../japa/japa_session_controller.dart';

enum _Step { intro, ageGate, underage, phone }

/// Screen 4 of the first-run flow (docs/ONBOARDING.md §3) — "the only ask,"
/// framed as protecting practice already done rather than a gate before
/// starting. Also reachable later from the japa screen itself for someone
/// who skipped this the first time, since nothing about deferred signup
/// means never — see the japa screen's "Save your practice" action.
///
/// docs/ONBOARDING.md §7 / docs/PRD.md §4.5: the OTP ask is now an age
/// gate, not just signup. A verified-parental-consent flow and Family
/// Accounts (the two real DPDPA-compliant paths for an under-18 singer)
/// don't exist yet — there's no KYC integration, no parent-linked account
/// type, nothing to route into honestly. Rather than fake consent with a
/// checkbox (explicitly insufficient under DPDP Rules 2025) or quietly let
/// a minor through standard phone-OTP signup, an under-18 declaration ends
/// in an honest "not yet, but your practice keeps working" screen instead
/// of an account. That's the entire scope of the "routing" this screen
/// does today — building the Family Account path itself is separate,
/// larger work (docs/GAPS.md, "Gaps created by the August 18 scope
/// decisions").
class SavePracticeScreen extends ConsumerStatefulWidget {
  const SavePracticeScreen({super.key});

  @override
  ConsumerState<SavePracticeScreen> createState() =>
      _SavePracticeScreenState();
}

class _SavePracticeScreenState extends ConsumerState<SavePracticeScreen> {
  _Step _step = _Step.intro;
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// The arrival screen no longer sits reactively at the root deciding
  /// what to show (docs/FRONTEND_GUIDELINES.md §12 — it's a splash shown
  /// on every open now, not a gate), so finishing here has to say
  /// explicitly where to land: back to the root, replaced by the feed —
  /// always, signed in or not (viewers browse for free; the japa screen
  /// is one tap away from there, not a separate landing state depending
  /// on auth — see onboarding_arrival_screen.dart's _handleBegin for the
  /// same call made for a fresh app open).
  Future<void> _finish() async {
    final isar = ref.read(isarProvider);
    await setOnboardingComplete(isar);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FeedScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (!(previous?.isAuthenticated ?? false) && next.isAuthenticated) {
        // The mala chanted before this account existed is still sitting
        // locally — push it now rather than waiting for the next natural
        // sync trigger (see retryPendingSync's doc).
        unawaited(
          ref.read(japaSessionControllerProvider.notifier).retryPendingSync(),
        );
        unawaited(_finish());
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: switch (_step) {
                _Step.intro => _buildIntro(theme),
                _Step.ageGate => _buildAgeGate(theme),
                _Step.underage => _buildUnderage(theme),
                _Step.phone => _buildPhone(theme),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(ThemeData theme) {
    return Column(
      key: const ValueKey(_Step.intro),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Save your practice so it's here tomorrow — "
          'and on any phone you sign in from.',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'No ads, ever.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AnhadColors.duskTextSecondary),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.ageGate),
          child: const Text('Continue'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _finish,
          child: const Text('Maybe later'),
        ),
      ],
    );
  }

  Widget _buildAgeGate(ThemeData theme) {
    return Column(
      key: const ValueKey(_Step.ageGate),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Before we continue — are you 18 or older?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          "We ask because the account we're about to create is an adult "
          'account.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AnhadColors.duskTextSecondary),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => setState(() => _step = _Step.phone),
          child: const Text("I'm 18 or older"),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => setState(() => _step = _Step.underage),
          child: const Text("I'm under 18"),
        ),
      ],
    );
  }

  Widget _buildUnderage(ThemeData theme) {
    return Column(
      key: const ValueKey(_Step.underage),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "We're not ready for that yet.",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'A parent-managed account for young singers is coming, but it '
          "isn't built yet — so we can't save your practice to an account "
          'today. Your chanting keeps working exactly as it has been, '
          'right here on this phone.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AnhadColors.duskTextSecondary),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _finish,
          child: const Text('Continue practicing'),
        ),
      ],
    );
  }

  Widget _buildPhone(ThemeData theme) {
    final state = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final awaitingCode = state.phoneNumber != null;

    return Column(
      key: const ValueKey(_Step.phone),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          awaitingCode
              ? 'Enter the code sent to ${state.phoneNumber}'
              : 'Sign in with your phone number',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        if (!awaitingCode) ...[
          TextField(
            controller: _phoneController,
            enabled: !state.isSubmitting,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+919812345678',
            ),
            onSubmitted: (_) => _requestOtp(controller),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                state.isSubmitting ? null : () => _requestOtp(controller),
            child: state.isSubmitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send code'),
          ),
        ] else ...[
          TextField(
            controller: _codeController,
            enabled: !state.isSubmitting,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '6-digit code'),
            onSubmitted: (_) => _verifyOtp(controller),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                state.isSubmitting ? null : () => _verifyOtp(controller),
            child: state.isSubmitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verify'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: state.isSubmitting
                ? null
                : () {
                    _codeController.clear();
                    controller.changeNumber();
                  },
            child: const Text('Use a different number'),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 16),
          Text(
            state.error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AnhadColors.accentSindoor),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: state.isSubmitting ? null : _finish,
          child: const Text('Maybe later'),
        ),
      ],
    );
  }

  void _requestOtp(AuthController controller) {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) return;
    controller.requestOtp(phoneNumber);
  }

  void _verifyOtp(AuthController controller) {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    controller.verifyOtp(code);
  }
}
