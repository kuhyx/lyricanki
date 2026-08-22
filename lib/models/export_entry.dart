import 'package:lyricanki/models/vocab_card.dart';
import 'package:meta/meta.dart';

/// One song that was exported, as the history list shows it.
///
/// A view over a `crdt_sync` `Record`, not a storage type: the record's fields
/// are an opaque last-writer-wins map, so this is where they get names and
/// types. Kept immutable and documented in the style of [Track].
@immutable
class ExportEntry {
  /// Creates an entry.
  const ExportEntry({
    required this.trackId,
    required this.name,
    required this.artist,
    required this.path,
    required this.cardCount,
    required this.exportedAt,
    required this.lyrics,
    this.cards = const <VocabCard>[],
    this.unresolved = const <String>[],
    this.hidden = false,
  });

  /// LRCLIB's track id, and this entry's identity.
  ///
  /// Re-exporting the same song updates the entry in place rather than adding
  /// a second row, so this is the record id too.
  final int trackId;

  /// Track title, as it appeared in the picker.
  final String name;

  /// Performing artist.
  final String artist;

  /// Absolute path of the written `.apkg`.
  ///
  /// Comes from `ExportDestination`, never rebuilt by hand: on Android the
  /// file lives in external app storage, and a path assembled from the
  /// documents directory would point at a file nothing can read.
  final String path;

  /// How many cards were ticked at export time.
  final int cardCount;

  /// When the export completed.
  final DateTime exportedAt;

  /// The lyrics the deck was built from.
  ///
  /// Stored so a rebuild needs no network: the file can be regenerated on a
  /// plane, and LRCLIB is not consulted twice for a song already exported.
  /// A few KB per entry, against a deck that is hundreds of KB.
  final String lyrics;

  /// The cards that were exported, as they were exported.
  ///
  /// Stored rather than re-derived so the detail screen can show the deck
  /// offline and **without the dictionary pack** -- a rebuild needs the pack,
  /// and this screen already has to cope with it being absent. It is also the
  /// only honest record of what shipped: re-deriving would show what the deck
  /// *would* be built as today, which differs whenever words were unticked or
  /// the pack has since changed.
  ///
  /// Empty on records written before this field existed. Those fall back to
  /// deriving from [lyrics], labelled as such.
  final List<VocabCard> cards;

  /// Surfaces the pack could not resolve at export time.
  ///
  /// Kept beside [cards] because "which words were dropped" is half the
  /// answer to "what got exported".
  final List<String> unresolved;

  /// Whether the user hid this row.
  ///
  /// A field rather than a CRDT tombstone, deliberately: `LogStore.delete`
  /// is *sticky* -- once deleted on any device it can never come back -- so
  /// using it would make "hide" an irreversible, fleet-wide erasure. As a
  /// last-writer-wins field it can be unhidden, and it never destroys the
  /// record of an export that really happened.
  final bool hidden;

  /// Title and artist as one line, the form the list shows.
  String get label => artist.isEmpty ? name : '$name — $artist';

  @override
  bool operator ==(Object other) =>
      other is ExportEntry && other.trackId == trackId;

  @override
  int get hashCode => trackId.hashCode;

  @override
  String toString() => 'ExportEntry($trackId, $name)';
}
