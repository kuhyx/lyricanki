import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:lyricanki/models/export_entry.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/models/vocab_card.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Every song this device has exported, in a CRDT log.
///
/// A `crdt_sync` [LogStore] rather than a bespoke JSON file, because the same
/// history is meant to appear on every device: the log merges without a
/// server arbitrating, and the Firebase transport pushes it. Reads are always
/// local and synchronous-fast, so the list paints on launch without waiting
/// for a network tick -- which is the whole complaint this feature answers.
///
/// Querying deliberately lives here, not in the library: a `Record`'s fields
/// are an opaque map, so shaping them into [ExportEntry] is the app's job.
class ExportHistory {
  /// Creates a history over [store].
  ///
  /// Use [open] in the app; this constructor exists so tests can inject an
  /// in-memory persistence and never touch the real history file.
  ExportHistory(this._store);

  final LogStore _store;

  /// Filename the log is persisted under.
  static const String fileName = 'export_history.json';

  /// Opens the history for [deviceId], hydrating it from disk.
  ///
  /// **Application *support*, not documents.** On Linux
  /// `getApplicationDocumentsDirectory()` resolves to plain `$HOME`, so using
  /// it drops an `export_history.json` loose in the user's home directory --
  /// observed doing precisely that before this was changed. The support
  /// directory is the per-app private location (`~/.local/share/lyricanki` on
  /// Linux, app-private storage on Android), which is where internal state
  /// like this belongs.
  ///
  /// Deliberately *not* the external storage the `.apkg` files use: the
  /// history is the app's own bookkeeping, nothing else reads it, and keeping
  /// it out of external storage is what makes the missing-file row work --
  /// Android clearing external app storage takes the deck and leaves the
  /// history entry offering to rebuild it.
  ///
  /// [directoryOverride] is only set by tests, so a test run can never write
  /// into the live app's history -- the same hazard, and the same seam, as
  /// `ExportDestination.directoryOverride`.
  static Future<ExportHistory> open({
    required String deviceId,
    Directory? directoryOverride,
  }) async {
    final base = directoryOverride ?? await getApplicationSupportDirectory();
    if (!base.existsSync()) {
      await base.create(recursive: true);
    }
    final store = LogStore(
      persistence: FileLogPersistence(File(p.join(base.path, fileName))),
      nodeId: deviceId,
    );
    await store.load();
    return ExportHistory(store);
  }

  /// Fires after every change, so the list can re-derive itself.
  Stream<void> get changes => _store.changes;

  /// The whole log, for handing to `syncLog`.
  Log snapshot() => _store.snapshot();

  /// Swaps in a merged log after a sync tick.
  Future<void> replaceAll(Log merged) => _store.replaceAll(merged);

  /// Every entry, newest export first, hidden rows included.
  ///
  /// Tombstoned records are skipped: nothing in this app writes one, but a
  /// merged log from a future version could carry them.
  List<ExportEntry> all() {
    final entries = <ExportEntry>[
      for (final record in _store.values)
        if (!record.deleted) _toEntry(record),
    ]..sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    return entries;
  }

  /// Every entry the user has not hidden, newest first.
  List<ExportEntry> visible() => all().where((entry) => !entry.hidden).toList();

  /// Records a completed export, replacing any earlier one of the same track.
  ///
  /// Called *after* the `.apkg` is written, never before: recording first
  /// would list songs whose export then failed.
  Future<void> record({
    required Track track,
    required String path,
    required int cardCount,
    List<VocabCard> cards = const <VocabCard>[],
    List<String> unresolved = const <String>[],
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    // Re-export keeps the row's identity (Q: one entry, updated in place) and
    // deliberately clears `hidden`: the user just exported this song, so
    // hiding it earlier should not make the new export invisible.
    await _store.upsert(
      Record(
        id: '${track.id}',
        fields: <String, Field>{
          'name': (track.name, _store.nextHlc()),
          'artist': (track.artist, _store.nextHlc()),
          'path': (path, _store.nextHlc()),
          'cardCount': (cardCount, _store.nextHlc()),
          'exportedAt': (now.toIso8601String(), _store.nextHlc()),
          'lyrics': (track.plainLyrics, _store.nextHlc()),
          // Encoded as JSON rather than as nested fields: a crdt_sync Field
          // is a single last-writer-wins value, and the deck is written once
          // per export as a unit. Splitting it per card would let two devices
          // merge half of one export into half of another.
          'cards': (_encodeCards(cards), _store.nextHlc()),
          'unresolved': (jsonEncode(unresolved), _store.nextHlc()),
          'hidden': (false, _store.nextHlc()),
        },
      ),
    );
  }

  /// Hides or unhides [trackId], leaving the `.apkg` and the record alone.
  Future<void> setHidden(int trackId, {required bool hidden}) async {
    final existing = _store.get('$trackId');
    if (existing == null) return;
    await _store.upsert(
      Record(
        id: existing.id,
        fields: <String, Field>{
          ...existing.fields,
          'hidden': (hidden, _store.nextHlc()),
        },
      ),
    );
  }

  ExportEntry _toEntry(Record record) => ExportEntry(
    trackId: int.tryParse(record.id) ?? 0,
    name: _string(record, 'name'),
    artist: _string(record, 'artist'),
    path: _string(record, 'path'),
    cardCount: _int(record, 'cardCount'),
    exportedAt:
        DateTime.tryParse(_string(record, 'exportedAt')) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    lyrics: _string(record, 'lyrics'),
    cards: _cards(record),
    unresolved: _stringList(record, 'unresolved'),
    hidden: record.fields['hidden']?.$1 == true,
  );

  /// Serialises [cards] for storage. Field order matches the Anki note's.
  static String _encodeCards(List<VocabCard> cards) => jsonEncode(<Object>[
    for (final card in cards)
      <String, String>{
        'lemma': card.lemma,
        'pos': card.pos,
        'gloss': card.gloss,
        'line': card.line,
      },
  ]);

  /// Reads the stored deck back, tolerating anything that is not it.
  ///
  /// Every failure yields an empty list, which the detail screen reads as
  /// "written before this field existed" and handles by deriving from the
  /// lyrics. A malformed blob from a future version therefore degrades to the
  /// old behaviour rather than taking the screen down.
  List<VocabCard> _cards(Record record) {
    final raw = record.fields['cards']?.$1;
    if (raw is! String || raw.isEmpty) return const <VocabCard>[];
    final decoded = _tryDecode(raw);
    if (decoded is! List) return const <VocabCard>[];
    return <VocabCard>[
      for (final item in decoded)
        if (item is Map)
          VocabCard(
            lemma: _mapString(item, 'lemma'),
            pos: _mapString(item, 'pos'),
            gloss: _mapString(item, 'gloss'),
            line: _mapString(item, 'line'),
          ),
    ];
  }

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  static String _mapString(Map<Object?, Object?> map, String key) {
    final value = map[key];
    return value is String ? value : '';
  }

  /// Reads a JSON string list, defaulting to empty on anything else.
  List<String> _stringList(Record record, String field) {
    final raw = record.fields[field]?.$1;
    if (raw is! String || raw.isEmpty) return const <String>[];
    final decoded = _tryDecode(raw);
    if (decoded is! List) return const <String>[];
    return <String>[
      for (final item in decoded)
        if (item is String) item,
    ];
  }

  // Fields arrive from a merged log that another version of the app may have
  // written, so every read is defensive: a wrong type yields a usable default
  // rather than throwing and taking the whole list down with it.
  String _string(Record record, String field) {
    final value = record.fields[field]?.$1;
    return value is String ? value : '';
  }

  int _int(Record record, String field) {
    final value = record.fields[field]?.$1;
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}
