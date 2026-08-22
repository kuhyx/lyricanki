import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/history_sync.dart';

import 'export_history_fixtures.dart';

void main() {
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

  test('merges a peer device\'s history and keeps both songs', () async {
    // A whole tick against a fake Realtime Database: this device pushes its
    // own log, pulls the peer's, merges, and writes the result back.
    final history = await ExportHistory.open(
      deviceId: 'me',
      directoryOverride: root,
    );
    await history.record(track: despacito, path: '/a.apkg', cardCount: 147);

    final peerLog = await () async {
      final peerRoot = Directory('${root.path}/peer')..createSync();
      final peer = await ExportHistory.open(
        deviceId: 'peer',
        directoryOverride: peerRoot,
      );
      await peer.record(track: bailando, path: '/b.apkg', cardCount: 92);
      return logToJson(peer.snapshot());
    }();

    final pushed = <String, String>{};
    final client = FirebaseRestClient(
      databaseUrl: 'https://fake-rtdb.example.com',
      auth: _StubAuth(),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        // The device listing: one peer, plus ourselves (skipped).
        if (request.method == 'GET' && path.contains('lyricanki-sync')) {
          if (request.url.queryParameters['shallow'] == 'true') {
            return http.Response(jsonEncode({'peer': true, 'me': true}), 200);
          }
          if (path.contains('peer')) {
            return http.Response(jsonEncode(peerLog), 200);
          }
          return http.Response('null', 200);
        }
        if (request.method == 'PUT') {
          pushed[path] = request.body;
          return http.Response(request.body, 200);
        }
        return http.Response('null', 200);
      }),
    );

    final count = await syncHistory(
      history: history,
      deviceId: 'me',
      firebaseFactory: () async => client,
    );

    expect(count, 2, reason: 'this device keeps both songs');
    expect(
      history.all().map((e) => e.name),
      containsAll(<String>[
        'Despacito',
        'Bailando',
      ]),
    );
    expect(pushed, isNotEmpty, reason: 'the merged log is pushed back');
  });
}

/// A token provider that never reaches the network: the merge, not the
/// sign-in, is what this suite exercises.
class _StubAuth implements FirebaseTokenProvider {
  @override
  Future<String> idToken() async => 'stub-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
