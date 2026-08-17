import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../japa/japa_screen.dart';

/// Placeholder for the vertical reel feed (`docs/PRD.md` §7.1).
///
/// Phase 1 replaces this with a `PageView.builder` full-screen feed,
/// category filtering, and the Pranam/Satsang/Prasad/Smaran/Sevak actions.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anhad'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Anhad',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const JapaScreen()),
              ),
              child: const Text('Start Japa'),
            ),
          ],
        ),
      ),
    );
  }
}
