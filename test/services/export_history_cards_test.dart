import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:path/path.dart' as p;

import 'export_history_fixtures.dart';

/// The exported deck, stored alongside the entry so the detail screen can
/// show what actually shipped rather than what a rebuild would produce today.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_cards'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<ExportHistory> open() =>
      ExportHistory.open(deviceId: 'test', directoryOverride: root);

  const cards = <VocabCard>[
    VocabCard(
      lemma: 'corazón',
      pos: 'noun',
      gloss: 'heart',
      line: 'Despacito, quiero respirar tu cuello',
    ),
    VocabCard(lemma: 'tu', pos: 'det/adj', gloss: 'your', line: 'tu cuello'),
  ];

  test('round-trips the exported cards', () async {
    final history = await open();
    await history.record(
      track: despacito,
      path: '/tmp/despacito.apkg',
      cardCount: cards.length,
      cards: cards,
      unresolved: <String>['ay', 'oh'],
    );

    final entry = history.all().single;
    expect(entry.cards, hasLength(2));
    expect(entry.cards.first.lemma, 'corazón');
    expect(entry.cards.first.gloss, 'heart');
    // The context line is the whole point: it is how the word became a card.
    expect(entry.cards.first.line, 'Despacito, quiero respirar tu cuello');
    expect(entry.cards.last.pos, 'det/adj');
    expect(entry.unresolved, <String>['ay', 'oh']);
  });

  test('survives a reopen from disk', () async {
    final first = await open();
    await first.record(
      track: despacito,
      path: '/tmp/d.apkg',
      cardCount: 2,
      cards: cards,
      unresolved: <String>['ay'],
    );

    final reopened = await open();
    expect(reopened.all().single.cards.first.lemma, 'corazón');
    expect(reopened.all().single.unresolved, <String>['ay']);
  });

  test('an export with no cards passed stores an empty deck', () async {
    // The pre-existing call shape. It must keep working, and must read back
    // as "nothing stored" so the screen falls back to deriving.
    final history = await open();
    await history.record(
      track: despacito,
      path: '/tmp/d.apkg',
      cardCount: 0,
    );

    expect(history.all().single.cards, isEmpty);
    expect(history.all().single.unresolved, isEmpty);
  });

  group('a log written by another version', () {
    void seed(String json) =>
        File(p.join(root.path, ExportHistory.fileName)).writeAsStringSync(json);

    const hlc = '2026-08-22T15:34:20.858Z-0000-other';

    /// Builds a one-record log whose `cards` field holds [cardsField].
    ///
    /// Written as raw JSON rather than through ExportHistory, which always
    /// writes well-typed values -- the point is what arrives from a device
    /// running a different version of the app.
    String logWith(String cardsField) {
      final encoded = jsonEncode(cardsField);
      return '{"36856755":{"id":"36856755","fields":{'
          '"name":["Despacito","$hlc"],'
          '"cards":[$encoded,"$hlc"],'
          '"unresolved":[$encoded,"$hlc"]'
          '},"deleted":false,"deleted_hlc":null}}';
    }

    test('reads an entry that predates the cards field', () async {
      seed(
        '{"36856755":{"id":"36856755","fields":{'
        '"name":["Despacito","$hlc"]'
        '},"deleted":false,"deleted_hlc":null}}',
      );

      // Empty, not a crash: this is exactly the state every song exported
      // before this feature is in, and the screen derives a list instead.
      expect((await open()).all().single.cards, isEmpty);
    });

    test('ignores a cards field that is not JSON', () async {
      seed(logWith('not json at all'));
      expect((await open()).all().single.cards, isEmpty);
    });

    test('ignores a cards field that decodes to the wrong shape', () async {
      seed(logWith('{"lemma":"x"}'));
      expect((await open()).all().single.cards, isEmpty);
    });

    test('substitutes blanks for wrongly-typed card fields', () async {
      seed(logWith('[{"lemma":"corazón","pos":42,"gloss":null}]'));

      final card = (await open()).all().single.cards.single;
      expect(card.lemma, 'corazón');
      // A wrong type must not take the whole list down with it.
      expect(card.pos, '');
      expect(card.gloss, '');
      expect(card.line, '');
    });

    test('keeps only the strings in an unresolved list', () async {
      seed(logWith('["ay",7,"oh"]'));
      expect((await open()).all().single.unresolved, <String>['ay', 'oh']);
    });
  });
}
