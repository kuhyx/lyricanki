import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/screens/pack_screen.dart';
import 'package:lyricanki/screens/review_screen.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/services/pack/pack_store.dart';
import 'package:sqlite3/sqlite3.dart';

/// Pixel 6a geometry (1080x2400 at 2.625 dpr, real status + nav insets).
void pixel6a(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625
    ..padding = const FakeViewPadding(top: 132, bottom: 63);
  addTearDown(tester.view.reset);
}

/// A pack of [n] distinct words, the size of a real song's card list.
DeckSession bigSession(int n) {
  final db = sqlite3.openInMemory()
    ..execute('''
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE forms (form TEXT, lemma TEXT, pos TEXT, PRIMARY KEY (form, lemma, pos));
CREATE TABLE senses (lemma TEXT, pos TEXT, gloss_en TEXT DEFAULT '', PRIMARY KEY (lemma, pos));
INSERT INTO meta VALUES ('pack_type', 'latin');
''');
  final words = <String>[
    for (var i = 0; i < n; i++)
      'pal${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}',
  ];
  for (final w in words) {
    db
      ..execute('INSERT INTO forms VALUES (?, ?, ?)', <String>[w, w, 'noun'])
      ..execute('INSERT INTO senses VALUES (?, ?, ?)', <String>[
        w,
        'noun',
        'gloss of $w',
      ]);
  }
  return DeckSession(pack: PackReader.fromDatabase(db), languageCode: 'es')
    ..load(
      Track(
        id: 1,
        name: 'Big song',
        artist: 'A',
        durationSeconds: 1,
        plainLyrics: words.join(' '),
      ),
    );
}

int _scrollableOverflow(WidgetTester tester) {
  var worst = 0;
  for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
    if (s.axisDirection == AxisDirection.down ||
        s.axisDirection == AxisDirection.up) {
      final extent = s.position.maxScrollExtent;
      if (extent > worst) worst = extent.ceil();
    }
  }
  return worst;
}

void main() {
  testWidgets('review fits one screen at 147 cards', (tester) async {
    pixel6a(tester);
    final session = bigSession(147);
    expect(session.entries, hasLength(147));
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(session: session, onExport: () async => 'ok'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_scrollableOverflow(tester), 0);
    Finder exportCount(String n) => find.descendant(
      of: find.byKey(const Key('review-export')),
      matching: find.text(n),
    );
    expect(exportCount('147'), findsOneWidget);
    // Primary action is on-screen and above the nav-bar inset.
    final y = tester.getBottomLeft(find.byType(FilledButton)).dy;
    expect(y, lessThanOrEqualTo(2400 / 2.625 - 63 / 2.625));
    // First tile toggles on tap.
    await tester.tap(find.byKey(const ValueKey<String>('cell-0')));
    await tester.pump();
    expect(exportCount('146'), findsOneWidget);
    // Detail lives behind long-press, not dropped.
    await tester.longPress(find.byKey(const ValueKey<String>('cell-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('gloss of palab'), findsWidgets);
    session.pack.close();
  });

  testWidgets('pack screen fits one screen', (tester) async {
    pixel6a(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: PackScreen(store: PackStore(), language: 'es'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_scrollableOverflow(tester), 0);
    expect(find.byType(ListView), findsNothing);
    expect(find.byKey(const Key('pack-download')), findsOneWidget);
  });
}
