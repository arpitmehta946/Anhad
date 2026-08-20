import 'package:flutter/material.dart';

import 'features/onboarding/onboarding_arrival_screen.dart';
import 'theme/app_theme.dart';

/// Lets a screen find out when another route is pushed on top of it (and
/// when it comes back) — the feed screen uses this to pause reel video/
/// audio the moment the japa screen (or anything else) covers it, rather
/// than leaving a reel playing with sound behind a screen meant for
/// eyes-closed, screen-off chanting.
final routeObserver = RouteObserver<PageRoute<void>>();

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
      navigatorObservers: [routeObserver],
      // The sapta swara arrival screen (docs/FRONTEND_GUIDELINES.md §12)
      // is shown on every open, not just a new user's first one — it
      // decides where "Begin" actually leads (mid onboarding, straight
      // into practice, or straight into the signed-in app) once it knows
      // the auth/onboarding state, rather than this widget gating on it
      // up front.
      home: const OnboardingArrivalScreen(),
    );
  }
}
