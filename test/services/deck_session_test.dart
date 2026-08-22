import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/track.dart';
import 'package:lyricanki/services/deck_session.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';

import 'pack/pack_reader_test.dart' show buildPack;

Track trackWith(String lyrics) => Track(
  id: 1,
  name: 'Test',
  artist: 'Artist',
  durationSeconds: 60,
  plainLyrics: lyrics,
);

void main() {
  late DeckSession session;

  setUp(() {
    session = DeckSession(
      pack: PackReader.fromDatabase(buildPack()),
      languageCode: 'es',
    );
  });
  tearDown(() {
    session.pack.close();
    session.dispose();
  });

  group('load', () {
    test('starts with nothing', () {
      expect(session.track, isNull);
      expect(session.entries, isEmpty);
      expect(session.selectedCount, 0);
    });

    test('selects every card by default', () {
      // Q3: inclusion is the user's choice, made by unticking. The app never
      // decides a word is too common to be worth a card.
      session.load(trackWith('Corazón suave'));
      expect(session.entries, hasLength(2));
      expect(session.entries.every((e) => e.selected), isTrue);
      expect(session.selectedCount, 2);
    });

    test('records the track and its unresolved surfaces', () {
      session.load(trackWith('Corazón dididiri'));
      expect(session.track!.name, 'Test');
      expect(session.unresolved, <String>['dididiri']);
    });

    test('replaces a previous draft rather than appending', () {
      session
        ..load(trackWith('Corazón'))
        ..load(trackWith('Suave'));
      expect(session.entries, hasLength(1));
      expect(session.entries.single.card.lemma, 'suave');
    });

    test('notifies listeners', () {
      var calls = 0;
      session
        ..addListener(() => calls++)
        ..load(trackWith('Corazón'));
      expect(calls, 1);
    });
  });

  group('selection', () {
    setUp(() => session.load(trackWith('Corazón suave')));

    test('toggle flips one entry and leaves the others', () {
      session.toggle(0);
      expect(session.entries[0].selected, isFalse);
      expect(session.entries[1].selected, isTrue);
      expect(session.selectedCount, 1);
    });

    test('toggle is reversible', () {
      session
        ..toggle(0)
        ..toggle(0);
      expect(session.entries[0].selected, isTrue);
    });

    test('selectNone unticks everything', () {
      session.selectNone();
      expect(session.selectedCount, 0);
      expect(session.selectedCards, isEmpty);
    });

    test('selectAll re-ticks everything', () {
      session
        ..selectNone()
        ..selectAll();
      expect(session.selectedCount, 2);
    });

    test('selectedCards reflects the ticks, in order', () {
      session.toggle(0);
      expect(session.selectedCards.single.lemma, 'suave');
    });

    test('entries and unresolved are unmodifiable views', () {
      expect(
        () => session.entries.add(session.entries.first),
        throwsUnsupportedError,
      );
      expect(() => session.unresolved.add('x'), throwsUnsupportedError);
    });
  });

  group('export', () {
    test('writes only the ticked cards', () async {
      session
        ..load(trackWith('Corazón suave'))
        ..toggle(0);
      final dir = Directory.systemTemp.createTempSync('lyricanki_export');
      try {
        final path = '${dir.path}/out.apkg';
        final size = await session.export(path);
        expect(size, greaterThan(0));
        expect(File(path).existsSync(), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('falls back to a deck name when no track is loaded', () async {
      final dir = Directory.systemTemp.createTempSync('lyricanki_export');
      try {
        // No track loaded, so no cards -- but it must not throw.
        final size = await session.export('${dir.path}/out.apkg');
        expect(size, greaterThan(0));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('ReviewEntry', () {
    test('toggled flips selection and keeps the card', () {
      session.load(trackWith('Corazón'));
      final entry = session.entries.single;
      final flipped = entry.toggled();
      expect(flipped.selected, isNot(entry.selected));
      expect(flipped.card, entry.card);
    });
  });
}
