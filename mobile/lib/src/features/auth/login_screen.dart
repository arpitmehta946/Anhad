import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import 'auth_controller.dart';

/// Phone-OTP sign-in: phone number → request code → enter code → done.
/// Replaces the Phase 0 dev-token dialog now that the real auth endpoints
/// are wired up (api/internal/server/auth.go).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final theme = Theme.of(context);
    final awaitingCode = state.phoneNumber != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Anhad',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  awaitingCode
                      ? 'Enter the code sent to ${state.phoneNumber}'
                      : 'Sign in with your phone number',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AnhadColors.duskTextSecondary),
                ),
                const SizedBox(height: 32),
                if (!awaitingCode) ..._phoneStep(state, controller)
                else ..._codeStep(state, controller),
                if (state.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AnhadColors.accentSindoor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep(AuthState state, AuthController controller) {
    return [
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
            ? const _ButtonSpinner()
            : const Text('Send code'),
      ),
    ];
  }

  List<Widget> _codeStep(AuthState state, AuthController controller) {
    return [
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
            ? const _ButtonSpinner()
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
    ];
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

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
