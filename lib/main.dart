// coverage:ignore-file
// Bootstrap only: wiring that cannot be exercised without a real app host.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lyricanki/screens/song_search_screen.dart';

void main() {
  runApp(const LyricankiApp());
}

/// Root of the app. Theming comes entirely from `design_system` -- there is
/// deliberately no local theme.dart here.
class LyricankiApp extends StatelessWidget {
  /// Creates the root widget.
  const LyricankiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'lyricanki',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const SongSearchScreen(),
    );
  }
}
