import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/review_screen.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';

import '../services/pack/pack_reader_test.dart' show buildPack;

DeckSession sessionWith(String lyrics) {
  final session = DeckSession(
    pack: PackReader.fromDatabase(buildPack()),
    languageCode: 'es',
  );
  if (lyrics.isNotEmpty) {
    session.load(
      Track(
        id: 1,
        name: 'Despacito',
        artist: 'Luis Fonsi',
        durationSeconds: 273,
        plainLyrics: lyrics,
      ),
    );
  }
  return session;
}

Future<void> pump(
  WidgetTester tester,
  DeckSession session, {
  Future<String> Function()? onExport,
}) => tester.pumpWidget(
  MaterialApp(
    home: ReviewScreen(
      session: session,
      onExport: onExport ?? () async => 'Exported',
    ),
  ),
);

void main() {
  testWidgets('lists every candidate word, ticked by default', (tester) async {
    // Q3: nothing is filtered out; the user unticks what they already know.
    final session = sessionWith('Corazón suave');
    await pump(tester, session);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.textContaining('corazón'), findsOneWidget);
    expect(find.text('Export 2 cards'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('shows the gloss and part of speech on each row', (tester) async {
    final session = sessionWith('Corazón');
    await pump(tester, session);
    expect(find.text('corazón  ·  noun'), findsOneWidget);
    expect(find.text('heart'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('unticking a word drops it from the export count', (
    tester,
  ) async {
    final session = sessionWith('Corazón suave');
    await pump(tester, session);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('Export 1 cards'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('None unticks everything and disables export', (tester) async {
    final session = sessionWith('Corazón suave');
    await pump(tester, session);
    await tester.tap(find.text('None'));
    await tester.pump();
    expect(find.text('Export 0 cards'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    session.pack.close();
  });

  testWidgets('All re-ticks everything', (tester) async {
    final session = sessionWith('Corazón suave');
    await pump(tester, session);
    await tester.tap(find.text('None'));
    await tester.pump();
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('Export 2 cards'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('names the unresolved words rather than hiding them', (
    tester,
  ) async {
    // A real Spanish word here means the pack regressed, so it is surfaced.
    final session = sessionWith('Corazón dididiri woah');
    await pump(tester, session);
    expect(find.text('2 words not in the dictionary'), findsOneWidget);
    expect(find.text('dididiri, woah'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('omits the unresolved note when everything resolved', (
    tester,
  ) async {
    final session = sessionWith('Corazón');
    await pump(tester, session);
    expect(find.textContaining('not in the dictionary'), findsNothing);
    session.pack.close();
  });

  testWidgets('shows the track name in the title', (tester) async {
    final session = sessionWith('Corazón');
    await pump(tester, session);
    expect(find.text('Despacito'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('falls back to a generic title with no track', (tester) async {
    final session = sessionWith('');
    await pump(tester, session);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('No words yet'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('exporting reports the result to the user', (tester) async {
    final session = sessionWith('Corazón');
    await pump(tester, session, onExport: () async => 'Exported 1 card');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Exported 1 card'), findsOneWidget);
    session.pack.close();
  });
}
