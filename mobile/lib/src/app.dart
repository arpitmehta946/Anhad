import 'package:flutter/material.dart';

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
      home: const FeedScreen(),
    );
  }
}
