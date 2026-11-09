import 'package:design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/review_screen.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/widgets/vocab_card_cell.dart';
import 'package:lyricanki/widgets/vocab_card_tile.dart';

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
    expect(find.byType(VocabCardCell), findsNWidgets(2));
    expect(find.textContaining('corazón'), findsOneWidget);
    expect(find.text('Export 2 cards'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('shows the gloss and part of speech on each cell', (
    tester,
  ) async {
    final session = sessionWith('Corazón');
    await pump(tester, session);
    expect(find.text('corazón'), findsOneWidget);
    expect(find.text('noun'), findsOneWidget);
    expect(find.text('heart'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('unticking a word drops it from the export count', (
    tester,
  ) async {
    final session = sessionWith('Corazón suave');
    await pump(tester, session);
    await tester.tap(find.byType(VocabCardCell).first);
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
    await tester.tap(find.text('2 words not in the dictionary'));
    await tester.pumpAndSettle();
    expect(find.text('dididiri, woah'), findsOneWidget);
    session.pack.close();
  });

  testWidgets('the unresolved sheet spans the phone and hugs its text', (
    tester,
  ) async {
    // Pixel 6a: 411x914 dp. On device the sheet came up a third of the width
    // and over half the height, a narrow empty column (2026-11-08).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final session = sessionWith('Corazón dididiri woah');
    // The app's own theme: the default one hid the narrow sheet.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: ReviewScreen(session: session, onExport: () async => 'ok'),
      ),
    );
    await tester.tap(find.text('2 words not in the dictionary'));
    await tester.pumpAndSettle();
    final sheet = tester.getSize(find.byType(BottomSheet));
    final screen = tester.getSize(find.byType(Scaffold).first);
    expect(sheet.width, screen.width);
    expect(
      tester.getSize(find.byType(UnresolvedWordsNote)).width,
      screen.width,
    );
    expect(sheet.height, lessThan(screen.height / 4));
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

  testWidgets('a mouse drag pages the cards on desktop', (tester) async {
    // Flutter's default desktop scroll behaviour ignores mouse drags, so the
    // Linux build was stuck on page 1 of the deck.
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = sessionWith('Corazón está suave, vamos, dame las tus me');
    await pump(tester, session);
    final first = find.byKey(const ValueKey<String>('cell-0'));
    expect(first.hitTestable(), findsOneWidget);
    await tester.dragFrom(
      const Offset(1000, 300),
      const Offset(-900, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(first.hitTestable(), findsNothing);
    session.pack.close();
  });
}
