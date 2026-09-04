import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import 'auth_controller.dart';

/// The plain, dedicated "you need to sign in" screen
/// (docs/FRONTEND_GUIDELINES.md §9: say what happened and what to do) —
/// reached whenever an authenticated action fails because there's no
/// usable session (features/auth/auth_error.dart's showAuthAwareSnackBar),
/// never a generic "something went wrong."
///
/// Deliberately not SavePracticeScreen: that screen is the onboarding
/// "save your practice" pitch, complete with an intro step, an age gate,
/// and a "Maybe later" that marks onboarding *complete* — all correct for
/// a first-time ask, all wrong for someone who already has an account and
/// just needs to sign back into it. This is just the phone/OTP form, with
/// copy that says why it's here.
class SignInPromptScreen extends ConsumerStatefulWidget {
  const SignInPromptScreen({super.key});

  @override
  ConsumerState<SignInPromptScreen> createState() =>
      _SignInPromptScreenState();
}

class _SignInPromptScreenState extends ConsumerState<SignInPromptScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Signing back in successfully closes this screen on its own — the
    // person resumes exactly wherever the failed action left them, rather
    // than having to navigate back manually.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (!(previous?.isAuthenticated ?? false) && next.isAuthenticated) {
        Navigator.of(context).pop();
      }
    });

    final state = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final awaitingCode = state.phoneNumber != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "You're signed out",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign back in with your phone number to continue.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AnhadColors.duskTextSecondary),
                ),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: awaitingCode
                      ? _buildCodeStep(theme, state, controller)
                      : _buildPhoneStep(theme, state, controller),
                ),
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
                  onPressed: state.isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep(
      ThemeData theme, AuthState state, AuthController controller) {
    return Column(
      key: const ValueKey('phone'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          onPressed: state.isSubmitting ? null : () => _requestOtp(controller),
          child: state.isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send code'),
        ),
      ],
    );
  }

  Widget _buildCodeStep(
      ThemeData theme, AuthState state, AuthController controller) {
    return Column(
      key: const ValueKey('code'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the code sent to ${state.phoneNumber}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
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
          onPressed: state.isSubmitting ? null : () => _verifyOtp(controller),
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
    );
  }
}
