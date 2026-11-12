import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show kE2ePassphraseKey;
import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/history_sync.dart';

import 'export_history_fixtures.dart';
import 'fake_rtdb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('sync'));
  tearDown(() => root.deleteSync(recursive: true));

  test('does nothing when this device is not signed in', () async {
    // Not being set up is a normal state, not an error: the app keeps
    // working against its local log and simply does not share it.
    final history = await ExportHistory.open(
      deviceId: 'd',
      directoryOverride: root,
    );
    await history.record(track: despacito, path: '/a.apkg', cardCount: 147);

    final count = await syncHistory(
      history: history,
      deviceId: 'd',
      firebaseFactory: () async => null,
    );

    expect(count, isNull);
    expect(history.all(), hasLength(1), reason: 'local history is untouched');
  });

  test('points at lyricanki\'s own path, not another app\'s', () {
    // Every app in the fleet shares one database, so a collision here would
    // merge two apps' logs into each other.
    expect(kSyncPathPrefix, 'lyricanki-sync/devices');
  });

  test('carries the shared project identifiers', () {
    // Committed on purpose: the key is a public identifier that already ships
    // in every APK, and the rules are what protect the data.
    expect(kSyncApp.project.apiKey, isNotEmpty);
    expect(kSyncApp.expectedUid, isNotEmpty);
    // The regional host: the plain firebaseio.com form 404s in a way that
    // reads like an auth failure.
    expect(kSyncApp.project.databaseUrl, contains('europe-west1'));
  });

  group('end-to-end encryption', () {
    setUp(() {
      e2eArgon2Params = const Argon2Params(
        memoryKiB: 8,
        iterations: 1,
        parallelism: 1,
      );
      // The copy memo is process-global; each test starts from a fresh db.
      resetE2eCopyMemo();
    });

    Future<ExportHistory> mine() async {
      final history = await ExportHistory.open(
        deviceId: 'me',
        directoryOverride: root,
      );
      await history.record(track: despacito, path: '/a.apkg', cardCount: 147);
      return history;
    }

    test('merges an old plaintext peer and pushes only ciphertext', () async {
      installFakeSecureStorage(initial: {kE2ePassphraseKey: 'test-passphrase'});
      final db = FakeRtdb();
      // A peer still on a plaintext build: its log sits at the old prefix,
      // which the one-time copy must carry over.
      final peerRoot = Directory('${root.path}/peer')..createSync();
      final peer = await ExportHistory.open(
        deviceId: 'peer',
        directoryOverride: peerRoot,
      );
      await peer.record(track: bailando, path: '/b.apkg', cardCount: 92);
      await db.client().putFileText(
        '$kSyncPathPrefix/peer/${ExportHistory.fileName}',
        logToJson(peer.snapshot()),
        message: 'seed',
      );
      db.clearWrites();
      final history = await mine();

      final count = await syncHistory(
        history: history,
        deviceId: 'me',
        firebaseFactory: () async => db.client(),
      );

      expect(count, 2, reason: 'the old peer is merged through the copy');
      expect(db.writes, isNotEmpty);
      for (final write in db.writes) {
        expect(write.key, isNot(startsWith('$kSyncPathPrefix/')));
        // Neither the songs nor the field names reach the server.
        for (final plain in ['Despacito', 'Bailando', '"artist"', 'lyrics']) {
          expect(write.value, isNot(contains(plain)), reason: write.key);
        }
      }
      expect(
        db.writes.map((w) => w.key),
        contains(startsWith('${E2eLayout.of(kSyncPathPrefix).prefix}/me/')),
      );
    });

    test('pushes nothing while this device has no passphrase', () async {
      installFakeSecureStorage();
      final db = FakeRtdb();

      await expectLater(
        syncHistory(
          history: await mine(),
          deviceId: 'me',
          firebaseFactory: () async => db.client(),
        ),
        throwsA(
          isA<HistorySyncLocked>()
              .having((e) => e.reason, 'reason', E2eLockReason.needsPassphrase)
              .having((e) => '$e', 'text', contains('needsPassphrase')),
        ),
      );
      expect(db.writes, isEmpty, reason: 'fail closed, never plaintext');
    });
  });
}
