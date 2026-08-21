import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';

void main() {
  group('fromJson', () {
    test('reads a full LRCLIB row', () {
      final track = Track.fromJson(<String, dynamic>{
        'id': 36856755,
        'trackName': 'Despacito',
        'artistName': 'Luis Fonsi',
        'duration': 273,
        'plainLyrics': 'Ay, ¡Fonsi!',
      });
      expect(track.id, 36856755);
      expect(track.name, 'Despacito');
      expect(track.artist, 'Luis Fonsi');
      expect(track.durationSeconds, 273);
      expect(track.plainLyrics, 'Ay, ¡Fonsi!');
    });

    test('normalises a null plainLyrics to empty, not null', () {
      // LRCLIB returns null for instrumentals and synced-only entries.
      final track = Track.fromJson(<String, dynamic>{
        'id': 1,
        'trackName': 'x',
        'artistName': 'y',
        'duration': 10,
        'plainLyrics': null,
      });
      expect(track.plainLyrics, '');
      expect(track.hasLyrics, isFalse);
    });

    test('tolerates missing name and artist', () {
      final track = Track.fromJson(<String, dynamic>{'id': 2, 'duration': 5});
      expect(track.name, '');
      expect(track.artist, '');
    });

    test('rounds a fractional duration', () {
      final track = Track.fromJson(<String, dynamic>{
        'id': 3,
        'duration': 272.6,
      });
      expect(track.durationSeconds, 273);
    });

    test('falls back to zero when duration is absent or not a number', () {
      expect(Track.fromJson(<String, dynamic>{'id': 4}).durationSeconds, 0);
      expect(
        Track.fromJson(<String, dynamic>{
          'id': 5,
          'duration': 'x',
        }).durationSeconds,
        0,
      );
    });
  });

  group('hasLyrics', () {
    test('is false for whitespace-only lyrics', () {
      final track = Track.fromJson(<String, dynamic>{
        'id': 6,
        'plainLyrics': '   \n  ',
      });
      expect(track.hasLyrics, isFalse);
    });

    test('is true when there is real text', () {
      final track = Track.fromJson(<String, dynamic>{
        'id': 7,
        'plainLyrics': 'Despacito',
      });
      expect(track.hasLyrics, isTrue);
    });
  });

  group('durationLabel', () {
    test('pads seconds to two digits', () {
      const track = Track(
        id: 1,
        name: 'x',
        artist: 'y',
        durationSeconds: 273,
        plainLyrics: '',
      );
      expect(track.durationLabel, '4:33');
    });

    test('handles a sub-minute duration', () {
      const track = Track(
        id: 1,
        name: 'x',
        artist: 'y',
        durationSeconds: 9,
        plainLyrics: '',
      );
      expect(track.durationLabel, '0:09');
    });
  });

  group('identity', () {
    test('compares by id, since that is what gets pinned', () {
      const a = Track(
        id: 36856755,
        name: 'Despacito',
        artist: 'Luis Fonsi',
        durationSeconds: 273,
        plainLyrics: 'a',
      );
      const b = Track(
        id: 36856755,
        name: 'Despacito (Remix)',
        artist: 'Justin Bieber',
        durationSeconds: 229,
        plainLyrics: 'b',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when the id differs', () {
      const a = Track(
        id: 36856755,
        name: 'x',
        artist: 'y',
        durationSeconds: 1,
        plainLyrics: '',
      );
      const b = Track(
        id: 36844210,
        name: 'x',
        artist: 'y',
        durationSeconds: 1,
        plainLyrics: '',
      );
      expect(a, isNot(b));
      expect(a, isNot(equals('36856755')));
    });

    test('toString names the id and title', () {
      const track = Track(
        id: 1,
        name: 'Despacito',
        artist: 'y',
        durationSeconds: 1,
        plainLyrics: '',
      );
      expect(track.toString(), 'Track(1, Despacito)');
    });
  });
}
