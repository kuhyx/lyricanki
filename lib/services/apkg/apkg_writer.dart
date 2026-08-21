import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/services/apkg/anki_ids.dart';
import 'package:lyricanki/services/apkg/collection_config.dart';
import 'package:lyricanki/services/apkg/collection_schema.dart';
import 'package:sqlite3/sqlite3.dart';

/// Writes Anki `.apkg` decks.
///
/// The archive holds **exactly two entries**: `collection.anki2` (a ver-11
/// SQLite collection) and `media` (the literal `{}`). There is no audio, per
/// decision Q9, so the media map is always empty — but the entry itself is
/// mandatory: Anki rejects an archive without it.
class ApkgWriter {
  /// Creates a writer.
  ///
  /// [now] is injectable so golden tests can assert byte-stable output; it
  /// defaults to the current time, which is what Anki stamps notes with.
  ApkgWriter({required this.language, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Language code used in the guid key, e.g. `es`.
  final String language;

  final DateTime Function() _now;

  /// Builds the `.apkg` bytes for [cards] under [deckName].
  ///
  /// Cards failing [VocabCard.isExportable] are dropped rather than written:
  /// an empty gloss, or a gloss equal to the word, is a defect that would
  /// otherwise satisfy a naive non-empty check and ship a card teaching
  /// nothing. The caller decides which words to include; this is the last
  /// guard, not the filter.
  List<int> build({required List<VocabCard> cards, required String deckName}) {
    final exportable = cards.where((c) => c.isExportable).toList();
    final collection = _buildCollection(cards: exportable, deckName: deckName);

    final archive = Archive()
      ..addFile(
        ArchiveFile('collection.anki2', collection.length, collection),
      )
      // Anki's media map: name -> filename. Always empty here, never omitted.
      ..addFile(_mediaEntry());

    final encoded = ZipEncoder().encode(archive);
    return encoded;
  }

  /// Writes the deck for [cards] to [path] and returns the file.
  Future<File> writeToFile({
    required List<VocabCard> cards,
    required String deckName,
    required String path,
  }) async {
    final bytes = build(cards: cards, deckName: deckName);
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes);
  }

  ArchiveFile _mediaEntry() {
    final media = utf8.encode('{}');
    return ArchiveFile('media', media.length, media);
  }

  /// Builds the SQLite collection as bytes.
  ///
  /// sqlite3 has no in-memory serialise binding here, so the database is built
  /// in a temporary directory and read back. This is also the path that must
  /// work on Android, which is why it is proven on-device before any UI is
  /// built on top of it.
  Uint8ListLike _buildCollection({
    required List<VocabCard> cards,
    required String deckName,
  }) {
    final dir = Directory.systemTemp.createTempSync('lyricanki_apkg');
    final dbPath = '${dir.path}/collection.anki2';
    try {
      final db = sqlite3.open(dbPath);
      try {
        db.execute(collectionSchema);
        _insertCollectionRow(db, deckName: deckName);
        _insertNotes(db, cards);
      } finally {
        db.close();
      }
      return File(dbPath).readAsBytesSync();
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  void _insertCollectionRow(Database db, {required String deckName}) {
    final nowMs = _now().millisecondsSinceEpoch;
    // Anki stores the collection creation time in seconds, everything else in
    // milliseconds. Mixing the two shifts every due date by a factor of 1000.
    final createdSeconds = nowMs ~/ 1000;
    db.execute(
      'INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, '
      'decks, dconf, tags) VALUES (1, ?, ?, ?, ?, 0, 0, 0, ?, ?, ?, ?, ?)',
      <Object?>[
        createdSeconds,
        nowMs,
        nowMs,
        ankiSchemaVersion,
        buildConfJson(),
        buildModelsJson(deckName: deckName),
        buildDecksJson(deckName: deckName),
        buildDconfJson(),
        '{}',
      ],
    );
  }

  void _insertNotes(Database db, List<VocabCard> cards) {
    final nowMs = _now().millisecondsSinceEpoch;
    final nowSeconds = nowMs ~/ 1000;
    final noteStmt = db.prepare(
      'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, '
      'flags, data) VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, ?)',
    );
    final cardStmt = db.prepare(
      'INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, '
      'factor, reps, lapses, left, odue, odid, flags, data) '
      'VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, ?)',
    );
    try {
      for (var i = 0; i < cards.length; i++) {
        final card = cards[i];
        // Ids must be unique and are conventionally epoch-ms. Offsetting by
        // the index keeps them unique when many notes are written inside the
        // same millisecond, which is the common case.
        final noteId = nowMs + i;
        final fields = <String>[card.lemma, card.pos, card.gloss, card.line];
        noteStmt.execute(<Object?>[
          noteId,
          guidFor('$language|${card.lemma}'),
          modelId,
          nowSeconds,
          '',
          fields.join(fieldSeparator),
          card.lemma,
          csumFor(card.lemma),
          '',
        ]);
        // New card: type 0 (new), queue 0 (new), due = position in the deck.
        cardStmt.execute(<Object?>[noteId, noteId, deckId, nowSeconds, i, '']);
      }
    } finally {
      noteStmt.close();
      cardStmt.close();
    }
  }
}

/// The byte-list type `File.readAsBytesSync` returns.
typedef Uint8ListLike = List<int>;
