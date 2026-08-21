import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/services/apkg/anki_ids.dart';
import 'package:lyricanki/services/apkg/apkg_writer.dart';
import 'package:lyricanki/services/apkg/collection_schema.dart';
import 'package:sqlite3/sqlite3.dart';

/// Opens the `collection.anki2` inside [bytes] and hands it to [body].
///
/// The collection has to be written to disk to be opened, which is also the
/// path the app takes on Android.
T withCollection<T>(List<int> bytes, T Function(Database db) body) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.files.firstWhere((f) => f.name == 'collection.anki2');
  final dir = Directory.systemTemp.createTempSync('lyricanki_test');
  try {
    final path = '${dir.path}/collection.anki2';
    File(path).writeAsBytesSync(entry.content as List<int>);
    final db = sqlite3.open(path);
    try {
      return body(db);
    } finally {
      db.close();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  const cards = <VocabCard>[
    VocabCard(
      lemma: 'corazón',
      pos: 'noun',
      gloss: 'heart',
      line: 'Despacito',
    ),
    VocabCard(
      lemma: 'estar',
      pos: 'verb',
      gloss: 'to be',
      line: 'Ya, ya me está gustando más de lo normal',
    ),
  ];

  final writer = ApkgWriter(
    language: 'es',
    now: () => DateTime.utc(2026, 8, 21, 12),
  );

  group('archive shape', () {
    test('holds exactly collection.anki2 and media', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final names =
          ZipDecoder().decodeBytes(bytes).files.map((f) => f.name).toList()
            ..sort();
      expect(names, <String>['collection.anki2', 'media']);
    });

    test('media is the literal empty map, since Q9 forbids audio', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final archive = ZipDecoder().decodeBytes(bytes);
      final media = archive.files.firstWhere((f) => f.name == 'media');
      expect(utf8.decode(media.content as List<int>), '{}');
    });
  });

  group('collection row', () {
    test('declares schema version 11', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final ver = withCollection(
        bytes,
        (db) => db.select('SELECT ver FROM col').first['ver'],
      );
      expect(ver, ankiSchemaVersion);
      expect(ver, 11);
    });

    test('carries the default deck "1" alongside the target deck', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final decks = withCollection(bytes, (db) {
        final raw = db.select('SELECT decks FROM col').first['decks'] as String;
        return jsonDecode(raw) as Map<String, dynamic>;
      });
      expect(decks.keys, containsAll(<String>['1', '$deckId']));
    });

    test('stores crt in seconds and mod in milliseconds', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final row = withCollection(
        bytes,
        (db) => db.select('SELECT crt, mod FROM col').first,
      );
      final crt = row['crt'] as int;
      final mod = row['mod'] as int;
      expect(mod ~/ 1000, crt);
    });

    test(
      'uses the hardcoded model id so imports do not fork the note type',
      () {
        final bytes = writer.build(cards: cards, deckName: 'Despacito');
        final models = withCollection(bytes, (db) {
          final raw =
              db.select('SELECT models FROM col').first['models'] as String;
          return jsonDecode(raw) as Map<String, dynamic>;
        });
        expect(models.keys, <String>['$modelId']);
      },
    );
  });

  group('notes', () {
    test('writes one note per card with four separated fields', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final rows = withCollection(
        bytes,
        (db) => db.select('SELECT flds FROM notes ORDER BY id').toList(),
      );
      expect(rows.length, 2);
      final first = (rows.first['flds'] as String).split(fieldSeparator);
      expect(first, <String>['corazón', 'noun', 'heart', 'Despacito']);
    });

    test('guid matches the genanki golden for the es| key', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final guid = withCollection(
        bytes,
        (db) =>
            db.select("SELECT guid FROM notes WHERE sfld = 'corazón'").first,
      );
      expect(guid['guid'], guidFor('es|corazón'));
      expect(guid['guid'], r'vId^YY^F=-');
    });

    test('populates csum rather than genanki placeholder 0', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final rows = withCollection(
        bytes,
        (db) => db.select('SELECT sfld, csum FROM notes').toList(),
      );
      for (final row in rows) {
        expect(row['csum'], isNot(0));
        expect(row['csum'], csumFor(row['sfld'] as String));
      }
    });

    test(
      'is byte-identical across rebuilds, so re-import updates in place',
      () {
        final first = writer.build(cards: cards, deckName: 'Despacito');
        final second = writer.build(cards: cards, deckName: 'Despacito');
        List<Object?> guids(List<int> bytes) => withCollection(
          bytes,
          (db) => db
              .select('SELECT guid FROM notes ORDER BY sfld')
              .map((r) => r['guid'])
              .toList(),
        );
        expect(guids(first), guids(second));
      },
    );
  });

  group('cards', () {
    test('are new: type 0, queue 0, due by position', () {
      final bytes = writer.build(cards: cards, deckName: 'Despacito');
      final rows = withCollection(
        bytes,
        (db) =>
            db.select('SELECT type, queue, due, did FROM cards ORDER BY due'),
      );
      expect(rows.length, 2);
      for (final row in rows) {
        expect(row['type'], 0);
        expect(row['queue'], 0);
        expect(row['did'], deckId);
      }
      expect(rows.map((r) => r['due']).toList(), <int>[0, 1]);
    });
  });

  group('export guard', () {
    test('drops a card with no usable gloss', () {
      const bad = VocabCard(lemma: 'x', pos: 'noun', gloss: '  ', line: 'y');
      expect(bad.isExportable, isFalse);
      final bytes = writer.build(cards: <VocabCard>[bad], deckName: 'D');
      final count = withCollection(
        bytes,
        (db) => db.select('SELECT COUNT(*) c FROM notes').first['c'],
      );
      expect(count, 0);
    });

    test('writes a homograph whose gloss matches the word', () {
      const me = VocabCard(lemma: 'me', pos: 'pron', gloss: 'me', line: 'y');
      final bytes = writer.build(cards: <VocabCard>[me], deckName: 'D');
      final flds = withCollection(
        bytes,
        (db) => db.select('SELECT flds FROM notes').first['flds'] as String,
      );
      expect(flds.split(fieldSeparator).first, 'me');
    });

    test('drops a card whose gloss is blank', () {
      const blank = VocabCard(lemma: 'x', pos: 'noun', gloss: '  ', line: 'y');
      expect(blank.isExportable, isFalse);
    });

    test('keeps a genuine gloss', () {
      expect(cards.first.isExportable, isTrue);
    });
  });

  group('writeToFile', () {
    test('creates the file and its parent directory', () async {
      final dir = Directory.systemTemp.createTempSync('lyricanki_out');
      try {
        final path = '${dir.path}/nested/despacito.apkg';
        final file = await writer.writeToFile(
          cards: cards,
          deckName: 'Despacito',
          path: path,
        );
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
