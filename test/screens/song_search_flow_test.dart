import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/services/lrclib_client.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'flow_harness.dart';

/// The search -> pick -> build -> export path, end to end.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lyricanki_flow');
    PathProviderPlatform.instance = FakePathProvider(root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('builds a deck from a picked track and exports it', (
    tester,
  ) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final store = storeIn(root);
    await pumpHome(tester, store);
    await pickTrack(tester);

    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.textContaining('Export'), findsOneWidget);

    await actAsync(
      tester,
      () => tester.tap(find.byType(FilledButton)),
      settleMs: 200,
    );

    // A real .apkg must land on disk, not just a message. It goes in an
    // `exports/` subdirectory: on Android that sits in external app storage,
    // which is reachable by the share sheet and by adb, unlike the app-private
    // documents directory the export originally used.
    final written = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.apkg'))
        .toList();
    expect(written, hasLength(1));
    expect(written.single.lengthSync(), greaterThan(0));
    expect(written.single.path, endsWith('Despacito.apkg'));
    store.close();
  });

  testWidgets('reports an LRCLIB failure when fetching the chosen track', (
    tester,
  ) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final store = storeIn(root);
    // Search succeeds so a row can be tapped; the follow-up get fails.
    final client = LrclibClient(
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode(<Map<String, dynamic>>[track])),
            200,
          );
        }
        return http.Response('', 503);
      }),
    );
    await pumpHome(tester, store, client: client);
    await pickTrack(tester);

    expect(find.textContaining('503'), findsOneWidget);
    store.close();
  });

  testWidgets('exports only the words left ticked', (tester) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final store = storeIn(root);
    await pumpHome(tester, store);
    await pickTrack(tester);

    final before = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .length;
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('Export ${before - 1} cards'), findsOneWidget);

    await actAsync(
      tester,
      () => tester.tap(find.byType(FilledButton)),
      settleMs: 200,
    );
    expect(find.textContaining('Exported ${before - 1} cards'), findsOneWidget);
    store.close();
  });

  testWidgets('hands the exported deck to another app', (tester) async {
    // Writing the file is not enough on Android: from API 30 the storage
    // picker cannot browse into Android/data, so without the share sheet the
    // user has no way to reach the deck they just exported. AnkiDroid
    // registers ACTION_SEND for application/apkg.
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final store = storeIn(root);
    final share = RecordingShare();
    await pumpHome(tester, store, share: share);
    await pickTrack(tester);

    await actAsync(
      tester,
      () => tester.tap(find.byType(FilledButton)),
      settleMs: 200,
    );

    expect(share.shared, hasLength(1));
    expect(share.shared.single, endsWith('Despacito.apkg'));
    expect(File(share.shared.single).existsSync(), isTrue);
    store.close();
  });
}
