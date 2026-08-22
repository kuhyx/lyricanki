import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/screens/song_search_screen.dart';
import 'package:lyricanki/services/apkg_share.dart';
import 'package:lyricanki/services/export_destination.dart';
import 'package:lyricanki/services/export_history.dart';
import 'package:lyricanki/services/lrclib_client.dart';
import 'package:lyricanki/services/pack/pack_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../services/pack/pack_reader_test.dart' show buildPack;

/// Shared scaffolding for the end-to-end screen flows.
///
/// Split out so both flow suites stay under the 250-line cap.

/// Points `getApplicationDocumentsDirectory` at a temporary directory, so the
/// export flow can run without an Android app sandbox.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  /// Creates a provider rooted at [root].
  FakePathProvider(this.root);

  /// Directory to report as the documents directory.
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getExternalStoragePath() async => root;

  /// Where the export history lives. Faked alongside the others so a test
  /// run never writes into the real per-app support directory.
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// A track whose lyrics resolve against the shared test pack.
const Map<String, dynamic> track = <String, dynamic>{
  'id': 36856755,
  'trackName': 'Despacito',
  'artistName': 'Luis Fonsi',
  'duration': 273,
  'plainLyrics': 'Corazón suave\nEstá vamo',
};

/// Writes the shared in-memory test pack to [path] as a real file.
void writePack(String path) {
  Directory(path).parent.createSync(recursive: true);
  buildPack()
    ..execute('VACUUM INTO ?', <String>[path])
    ..dispose();
}

/// A store that never really downloads, rooted at [root].
PackStore storeIn(Directory root) => PackStore(
  httpClient: MockClient((_) async => http.Response('', 200)),
  directoryOverride: root,
);

/// An LRCLIB client returning [track] for both search and get.
LrclibClient clientWithTrack() => LrclibClient(
  httpClient: MockClient((request) async {
    final body = request.url.path.contains('/search')
        ? <Map<String, dynamic>>[track]
        : track;
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  }),
);

/// Pumps the home screen and lets its initState pack check actually run.
///
/// Real dart:io cannot complete inside the test's fake-async zone, so the
/// settle has to happen inside [WidgetTester.runAsync].
/// Opens a history rooted at [root], so a test never touches the live one.
///
/// The device id is fixed rather than generated: a test that asserts on the
/// log's contents should not depend on a random uuid.
Future<ExportHistory> historyIn(Directory root) =>
    ExportHistory.open(deviceId: 'test-device', directoryOverride: root);

Future<void> pumpHome(
  WidgetTester tester,
  PackStore store, {
  LrclibClient? client,
  ExportDestination? destination,
  ApkgShare? share,
  ExportHistory? history,
  Future<int?> Function(ExportHistory, String)? syncHistory,
}) async {
  // The screen resolves a device id for the history log through
  // SharedPreferences, which has no binding under `flutter test`. Seeded here
  // rather than in each suite's setUp so every caller of pumpHome is covered.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.pumpWidget(
    MaterialApp(
      home: SongSearchScreen(
        client: client ?? clientWithTrack(),
        store: store,
        destination: destination,
        // The real one reaches the Android share sheet over a platform
        // channel, which throws MissingPluginException under flutter test.
        share: share ?? RecordingShare(),
        history: history,
        syncHistory: syncHistory,
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

/// Runs [action] with real async work allowed, then pumps a frame.
Future<void> actAsync(
  WidgetTester tester,
  Future<void> Function() action, {
  int settleMs = 100,
}) async {
  await tester.runAsync(() async {
    await action();
    await Future<void>.delayed(Duration(milliseconds: settleMs));
  });
  await tester.pumpAndSettle();
}

/// Searches for the track and taps its row, landing on the review screen.
Future<void> pickTrack(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Despacito');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  await actAsync(
    tester,
    () => tester.tap(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Despacito'),
      ),
    ),
  );
}

/// Records what was shared instead of reaching the platform channel.
class RecordingShare implements ApkgShare {
  /// Paths passed to [shareApkg], in call order.
  final List<String> shared = <String>[];

  @override
  Future<void> shareApkg(String path) async => shared.add(path);
}
