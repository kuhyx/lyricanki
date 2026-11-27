import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart' show Argon2Params, resetE2eCopyMemo;
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show kE2ePassphraseKey;
import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/history_sync.dart';
import 'package:lyricanki/services/sync_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../services/export_history_fixtures.dart';
import '../services/fake_rtdb.dart';
import 'flow_harness.dart';
import 'real_async.dart';

/// Offline-first rule (b) end to end: the real sync against a remote that is
/// down, then back. A write made while it is down stays local and reaches the
/// remote on the next automatic tick, with nobody tapping the sync button.
///
/// `song_search_autosync_test.dart` covers *when* ticks run with a stubbed
/// tick; this one proves the data actually arrives.
void main() {
  late Directory root;
  late FakeRtdb db;
  late int started;
  late int finished;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hist_offline');
    db = FakeRtdb()..offline = true;
    started = 0;
    finished = 0;
    // A real passphrase, or the tick ends `locked` and never retries.
    installFakeSecureStorage(initial: {kE2ePassphraseKey: 'test-passphrase'});
    e2eArgon2Params = const Argon2Params(
      memoryKiB: 8,
      iterations: 1,
      parallelism: 1,
    );
    resetE2eCopyMemo();
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// The production tick, pointed at [db] and counted.
  Future<int?> realTick(ExportHistory history, String deviceId) async {
    started++;
    try {
      return await syncHistory(
        history: history,
        deviceId: deviceId,
        firebaseFactory: () async => db.client(),
      );
    } finally {
      finished++;
    }
  }

  /// What a second device pulls from [db]: proof the push really landed,
  /// since the stored bytes are ciphertext.
  Future<List<int>> peerSees() async {
    final peer = await ExportHistory.open(
      deviceId: 'peer',
      directoryOverride: Directory('${root.path}/peer')..createSync(),
    );
    await syncHistory(
      history: peer,
      deviceId: 'peer',
      firebaseFactory: () async => db.client(),
    );
    return [for (final entry in peer.all()) entry.trackId];
  }

  testWidgets('a write made offline is pushed by the retry, no tap', (
    tester,
  ) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final history = (await tester.runAsync(() => historyIn(root)))!;
    await pumpHome(
      tester,
      storeIn(root),
      history: history,
      syncHistory: realTick,
    );
    await pumpUntil(tester, () => finished == 1);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

    // The write lands locally at once; its debounced tick fails too.
    await tester.runAsync(
      () => history.record(track: bailando, path: '/b.apkg', cardCount: 92),
    );
    expect(history.all().map((e) => e.trackId), [bailando.id]);
    await tester.pump(SyncScheduler.defaultDebounce);
    await pumpUntil(tester, () => finished == 2);
    expect(started, 2);
    expect(db.writes, isEmpty, reason: 'nothing reached the remote yet');
    expect(history.all().map((e) => e.trackId), [bailando.id]);

    db.offline = false;
    // Second failure in a row: the backoff has doubled from the first retry.
    await tester.pump(SyncScheduler.defaultFirstRetry * 2);
    await pumpUntil(tester, () => finished == 3);
    expect(started, 3, reason: 'the retry ran by itself');
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(await tester.runAsync(peerSees), [bailando.id]);
  });
}
