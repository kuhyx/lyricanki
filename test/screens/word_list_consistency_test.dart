import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/screens/export_detail_screen.dart';
import 'package:lyricanki/screens/review_screen.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/widgets/vocab_card_tile.dart';

import '../services/pack/pack_reader_test.dart' show buildPack;

/// The word list must look the same before and after export.
///
/// Enforced as a test rather than left as a convention: the two screens were
/// written months apart and would drift the moment the rendering was
/// duplicated, which is exactly what this feature was asked not to do.
const _cards = <VocabCard>[
  VocabCard(
    lemma: 'corazón',
    pos: 'noun',
    gloss: 'heart',
    line: 'Despacito, quiero respirar tu cuello',
  ),
];

ExportEntry _entry({List<VocabCard> cards = _cards}) => ExportEntry(
  trackId: 36856755,
  name: 'Despacito',
  artist: 'Luis Fonsi',
  path: '/present.apkg',
  cardCount: cards.length,
  exportedAt: DateTime(2026, 8, 22, 17, 45),
  lyrics: 'uno dos',
  cards: cards,
);

void main() {
  testWidgets('the detail screen renders the shared tile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExportDetailScreen(
          entry: _entry(),
          fileExists: (_) => true,
          onShare: () async {},
          onRebuild: () async {},
          onHide: () async {},
        ),
      ),
    );

    expect(find.byType(VocabCardTile), findsOneWidget);
    expect(find.text('corazón  ·  noun'), findsOneWidget);
    expect(find.text('heart'), findsOneWidget);
  });

  testWidgets('the review screen renders the same shared tile', (
    tester,
  ) async {
    final session =
        DeckSession(
          pack: PackReader.fromDatabase(buildPack()),
          languageCode: 'es',
        )..load(
          const Track(
            id: 1,
            name: 'Despacito',
            artist: 'Luis Fonsi',
            durationSeconds: 273,
            plainLyrics: 'Corazón',
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(session: session, onExport: () async => 'done'),
      ),
    );

    // Same widget type, same text, from a screen that ticks rather than
    // reads. A change to either propagates to both by construction.
    expect(find.byType(VocabCardTile), findsOneWidget);
    expect(find.text('corazón  ·  noun'), findsOneWidget);
    expect(find.text('heart'), findsOneWidget);
  });
}
