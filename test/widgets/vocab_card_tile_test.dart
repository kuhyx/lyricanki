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

    testWidgets('is read-only without onToggle', (tester) async {
      await tester.pumpWidget(_wrap(const VocabCardTile(card: _card)));

      // History is a record of what shipped, not a choice still being made.
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('ticks and reports back when onToggle is given', (
      tester,
    ) async {
      var toggled = 0;
      await tester.pumpWidget(
        _wrap(
          VocabCardTile(
            card: _card,
            selected: true,
            onToggle: () => toggled++,
          ),
        ),
      );

      final box = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(box.value, isTrue);

      await tester.tap(find.byType(CheckboxListTile));
      expect(toggled, 1);
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

      expect(find.text('2 words not in the dictionary'), findsOneWidget);
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

      expect(find.text('Words (3)'), findsOneWidget);
      expect(find.textContaining('exactly as they were exported'), findsOne);
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
      expect(find.textContaining('147 words now, against 120'), findsOne);
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

      expect(find.text('Words'), findsOneWidget);
      expect(find.textContaining('before lyricanki recorded'), findsOne);
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

      expect(find.textContaining('may differ'), findsOne);
      expect(find.textContaining('against'), findsNothing);
    });
  });
}
