import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/widgets/vocab_card_tile.dart';

const _card = VocabCard(
  lemma: 'corazón',
  pos: 'noun',
  gloss: 'heart',
  line: 'Despacito, quiero respirar tu cuello despacito',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('VocabCardTile', () {
    testWidgets('shows the whole Anki note: word, pos, gloss and line', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const VocabCardTile(card: _card)));

      expect(find.text('corazón  ·  noun'), findsOneWidget);
      expect(find.text('heart'), findsOneWidget);
      expect(find.text(_card.line), findsOneWidget);
    });

    testWidgets('is a read-only row', (tester) async {
      await tester.pumpWidget(_wrap(const VocabCardTile(card: _card)));

      // History is a record of what shipped, not a choice still being made.
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('omits the context row when the card has no line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const VocabCardTile(
            card: VocabCard(lemma: 'x', pos: 'noun', gloss: 'y', line: ''),
          ),
        ),
      );

      expect(find.text('y'), findsOneWidget);
      // An empty context row would be a stray blank line under every gloss.
      expect(find.byType(Text), findsNWidgets(2));
    });
  });

  group('UnresolvedWordsNote', () {
    testWidgets('names the words the pack could not resolve', (tester) async {
      await tester.pumpWidget(
        _wrap(const UnresolvedWordsNote(unresolved: <String>['ay', 'oh'])),
      );

      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('ay, oh'), findsOneWidget);
    });

    testWidgets('renders nothing when everything resolved', (tester) async {
      await tester.pumpWidget(
        _wrap(const UnresolvedWordsNote(unresolved: <String>[])),
      );

      expect(find.byType(Text), findsNothing);
    });
  });

  group('WordListHeader', () {
    testWidgets('calls a stored list exact', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const WordListHeader(
            count: 3,
            exact: true,
            cardCount: 3,
            empty: false,
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(kindOf(tester), WordListKind.exact);
      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    });

    testWidgets('flags a rebuild that disagrees with the export', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const WordListHeader(
            count: 147,
            exact: false,
            cardCount: 120,
            empty: false,
          ),
        ),
      );

      // The count sits directly under the "Cards" stat, so a silent
      // disagreement would read as a bug in one of the two numbers.
      expect(kindOf(tester), WordListKind.rebuiltDiffers);
      expect(find.text('147'), findsOneWidget);
      expect(find.text('≠ 120'), findsOneWidget);
    });

    testWidgets('explains an empty list rather than showing a blank', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const WordListHeader(
            count: 0,
            exact: false,
            cardCount: 5,
            empty: true,
          ),
        ),
      );

      expect(kindOf(tester), WordListKind.empty);
      expect(find.byIcon(Icons.storage_outlined), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('does not cite a mismatch when the counts agree', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const WordListHeader(
            count: 5,
            exact: false,
            cardCount: 5,
            empty: false,
          ),
        ),
      );

      expect(kindOf(tester), WordListKind.rebuilt);
      expect(find.textContaining('≠'), findsNothing);
    });
  });
}

WordListKind kindOf(WidgetTester tester) =>
    tester.widget<WordListHeader>(find.byType(WordListHeader)).kind;
