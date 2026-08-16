import 'package:flutter/material.dart';

/// Placeholder for the vertical reel feed (`docs/PRD.md` §7.1).
///
/// Phase 1 replaces this with a `PageView.builder` full-screen feed,
/// category filtering, and the Pranam/Satsang/Prasad/Smaran/Sevak actions.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Anhad',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
