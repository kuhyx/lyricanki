import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Entry screen: find a song, then turn its lyrics into a deck.
///
/// The search field and results land in M4; this is the shell so the app
/// boots and the theme wiring is exercised.
class SongSearchScreen extends StatelessWidget {
  /// Creates the search screen.
  const SongSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('lyricanki')),
      body: const Center(
        child: EmptyState(
          icon: Icons.library_music_outlined,
          title: 'No song yet',
          message: 'Search for a song to build a vocabulary deck from it.',
        ),
      ),
    );
  }
}
