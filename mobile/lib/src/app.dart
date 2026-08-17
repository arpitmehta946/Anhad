import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/feed/feed_screen.dart';
import 'theme/app_theme.dart';

class AnhadApp extends StatelessWidget {
  const AnhadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anhad',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.prabhat,
      darkTheme: AppTheme.dusk,
      themeMode: ThemeMode.dark,
      home: const _AuthGate(),
    );
  }
}

/// Shows the login screen until there's a signed-in session, then the app
/// itself — every screen behind this can assume it's talking to an
/// authenticated user.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);

    if (state.checkingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return state.isAuthenticated ? const FeedScreen() : const LoginScreen();
  }
}
