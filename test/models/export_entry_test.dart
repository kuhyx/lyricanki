import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/export_entry.dart';

ExportEntry entry({
  int trackId = 1,
  String name = 'Despacito',
  String artist = 'Luis Fonsi',
  bool hidden = false,
}) => ExportEntry(
  trackId: trackId,
  name: name,
  artist: artist,
  path: '/exports/song.apkg',
  cardCount: 147,
  exportedAt: DateTime(2026, 8, 22),
  lyrics: 'Sí, sabes que ya llevo un rato mirándote',
  hidden: hidden,
);

void main() {
  group('label', () {
    test('joins the title and the artist', () {
      expect(entry().label, 'Despacito — Luis Fonsi');
    });

    test('drops the separator when the artist is unknown', () {
      // LRCLIB rows can carry an empty artistName, and a row reading
      // "Despacito — " looks like a rendering bug.
      expect(entry(artist: '').label, 'Despacito');
    });
  });

  group('identity', () {
    test('two entries for the same track are equal', () {
      // The track id is the identity, so a re-export compares equal to the
      // row it replaces even though every other field changed.
      expect(entry(name: 'old'), entry(name: 'new'));
      expect(entry(name: 'old').hashCode, entry(name: 'new').hashCode);
    });

    test('different tracks are not equal', () {
      expect(entry(trackId: 1), isNot(entry(trackId: 2)));
    });

    test('is not equal to another type', () {
      expect(entry(), isNot('Despacito'));
    });
  });

  test('toString names the track it is for', () {
    expect(entry().toString(), 'ExportEntry(1, Despacito)');
  });
}
