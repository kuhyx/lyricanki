import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/screens/song_search_screen.dart';

void main() {
  testWidgets('shows an empty state until a song is chosen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SongSearchScreen()),
    );

    expect(find.text('lyricanki'), findsOneWidget);
    expect(find.text('No song yet'), findsOneWidget);
    expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
  });
}
