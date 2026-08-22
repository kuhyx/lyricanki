import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../screens/flow_harness.dart' show FakePathProvider;
import 'export_history_fixtures.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_history'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<ExportHistory> openIn(Directory dir, {String device = 'test'}) =>
      ExportHistory.open(deviceId: device, directoryOverride: dir);

  test('starts empty', () async {
    expect((await openIn(root)).all(), isEmpty);
  });

  test('records an export and reads it back', () async {
    final history = await openIn(root);

    await history.record(
      track: despacito,
      path: '/exports/Despacito.apkg',
      cardCount: 147,
    );

    final entries = history.all();
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Despacito');
    expect(entries.single.artist, 'Luis Fonsi');
    expect(entries.single.cardCount, 147);
    expect(entries.single.path, '/exports/Despacito.apkg');
    expect(entries.single.lyrics, despacito.plainLyrics);
    expect(entries.single.hidden, isFalse);
  });

  test('survives a full restart, not just a rebuild', () async {
    // The reported bug, exactly: export Despacito, kill the app, reopen it.
    // A store that only kept the entry in memory would pass every other test
    // in this file and still fail the user.
    await (await openIn(root)).record(
      track: despacito,
      path: '/exports/Despacito.apkg',
      cardCount: 147,
    );

    final reopened = await openIn(root);

    expect(reopened.all().single.name, 'Despacito');
    expect(
      File(p.join(root.path, ExportHistory.fileName)).existsSync(),
      isTrue,
      reason: 'the log is on disk, not merely in memory',
    );
  });

  test('re-exporting a track updates the row in place', () async {
    final history = await openIn(root);

    await history.record(
      track: despacito,
      path: '/exports/old.apkg',
      cardCount: 100,
      at: DateTime(2026, 8, 20),
    );
    await history.record(
      track: despacito,
      path: '/exports/new.apkg',
      cardCount: 147,
      at: DateTime(2026, 8, 22),
    );

    expect(history.all(), hasLength(1), reason: 'one entry, not two');
    expect(history.all().single.cardCount, 147);
    expect(history.all().single.path, '/exports/new.apkg');
  });

  test('keeps different tracks apart', () async {
    final history = await openIn(root);

    await history.record(track: despacito, path: '/a.apkg', cardCount: 147);
    await history.record(track: bailando, path: '/b.apkg', cardCount: 90);

    expect(history.all(), hasLength(2));
  });

  test('orders newest export first', () async {
    final history = await openIn(root);

    await history.record(
      track: despacito,
      path: '/a.apkg',
      cardCount: 1,
      at: DateTime(2026, 8, 20),
    );
    await history.record(
      track: bailando,
      path: '/b.apkg',
      cardCount: 2,
      at: DateTime(2026, 8, 22),
    );

    expect(history.all().map((e) => e.name), ['Bailando', 'Despacito']);
  });

  group('hiding', () {
    test('hidden rows leave all() but drop out of visible()', () async {
      final history = await openIn(root);
      await history.record(track: despacito, path: '/a.apkg', cardCount: 147);

      await history.setHidden(despacito.id, hidden: true);

      expect(history.visible(), isEmpty);
      expect(
        history.all().single.hidden,
        isTrue,
        reason: 'hiding must not destroy the record of a real export',
      );
    });

    test('a hidden row can be unhidden', () async {
      // The reason hide is a field and not a CRDT tombstone: a tombstone is
      // sticky and could never come back.
      final history = await openIn(root);
      await history.record(track: despacito, path: '/a.apkg', cardCount: 147);
      await history.setHidden(despacito.id, hidden: true);

      await history.setHidden(despacito.id, hidden: false);

      expect(history.visible(), hasLength(1));
    });

    test('hiding survives a restart', () async {
      final history = await openIn(root);
      await history.record(track: despacito, path: '/a.apkg', cardCount: 147);
      await history.setHidden(despacito.id, hidden: true);

      expect((await openIn(root)).visible(), isEmpty);
    });

    test('re-exporting a hidden track shows it again', () async {
      final history = await openIn(root);
      await history.record(track: despacito, path: '/a.apkg', cardCount: 147);
      await history.setHidden(despacito.id, hidden: true);

      await history.record(track: despacito, path: '/b.apkg', cardCount: 148);

      expect(
        history.visible(),
        hasLength(1),
        reason: 'a just-exported song must not be invisible',
      );
    });

    test('hiding an unknown track is a no-op', () async {
      final history = await openIn(root);

      await history.setHidden(999, hidden: true);

      expect(history.all(), isEmpty);
    });
  });

  test('notifies listeners when an export is recorded', () async {
    final history = await openIn(root);
    final seen = <void>[];
    final subscription = history.changes.listen(seen.add);

    await history.record(track: despacito, path: '/a.apkg', cardCount: 147);
    // The stream is a broadcast controller, so the event lands on a later
    // microtask than the write that caused it.
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(seen, isNotEmpty);
  });

  test('defaults to the app support directory when not overridden', () async {
    // The production call shape, with path_provider faked so the real
    // support directory is never touched by a test run. Not the *documents*
    // directory: on Linux that is plain $HOME, and the history landed loose
    // in the user's home folder until this moved.
    PathProviderPlatform.instance = FakePathProvider(root.path);
    addTearDown(() => PathProviderPlatform.instance = FakePathProvider('/'));

    final history = await ExportHistory.open(deviceId: 'test');
    await history.record(track: despacito, path: '/a.apkg', cardCount: 147);

    expect(
      File(p.join(root.path, ExportHistory.fileName)).existsSync(),
      isTrue,
    );
  });

  test('creates the directory when it does not exist yet', () async {
    final nested = Directory(p.join(root.path, 'not', 'there'));

    final history = await openIn(nested);

    expect(nested.existsSync(), isTrue);
    expect(history.all(), isEmpty);
  });
}
