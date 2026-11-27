import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/export_history.dart';

import 'export_history_fixtures.dart';

/// Writes racing a sync tick. A sync snapshots the log, goes to the network,
/// then swaps the merged result in. Sync runs by itself after every write, so
/// a write that lands while it is away is a normal event, not a corner case.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_race'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<ExportHistory> open() =>
      ExportHistory.open(deviceId: 'test', directoryOverride: root);

  test('a new export made mid-sync survives the merge', () async {
    final history = await open();
    await history.record(track: despacito, path: '/a.apkg', cardCount: 1);
    final takenBySync = history.snapshot();

    await history.record(track: bailando, path: '/b.apkg', cardCount: 2);
    await history.replaceAll(takenBySync);

    expect(history.all().map((e) => e.name), contains('Bailando'));
  });

  test('a hide made mid-sync survives the merge', () async {
    final history = await open();
    await history.record(track: despacito, path: '/a.apkg', cardCount: 1);
    final takenBySync = history.snapshot();

    await history.setHidden(despacito.id, hidden: true);
    await history.replaceAll(takenBySync);

    expect(history.visible(), isEmpty);
  });

  test('announces local writes, never the merge itself', () async {
    final history = await open();
    var writes = 0;
    final subscription = history.localWrites.listen((_) => writes++);
    addTearDown(subscription.cancel);

    await history.record(track: despacito, path: '/a.apkg', cardCount: 1);
    await history.setHidden(despacito.id, hidden: true);
    await history.setHidden(404, hidden: true);
    await history.replaceAll(history.snapshot());
    await Future<void>.delayed(Duration.zero);

    // A merge that announced itself would start the next sync, forever.
    expect(writes, 2);
  });
}
