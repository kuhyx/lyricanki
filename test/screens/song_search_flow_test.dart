import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/services/lrclib_client.dart';
import 'package:lyricanki/widgets/vocab_card_cell.dart';
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

    expect(find.byType(VocabCardCell), findsWidgets);
    expect(find.byKey(const Key('review-export')), findsOneWidget);

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

    // A failure glyph in the app bar; the cause is spoken, never painted.
    final glyph = tester.widget<Icon>(find.byIcon(Icons.cloud_off_outlined));
    expect(glyph.semanticLabel, contains('503'));
    expect(find.textContaining('503'), findsNothing);
    store.close();
  });

  testWidgets('exports only the words left ticked', (tester) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final store = storeIn(root);
    await pumpHome(tester, store);
    await pickTrack(tester);

    final count = find.descendant(
      of: find.byKey(const Key('review-export')),
      matching: find.byType(Text),
    );
    final before = int.parse(tester.widget<Text>(count).data!);
    await tester.tap(find.byType(VocabCardCell).first);
    await tester.pump();
    expect(tester.widget<Text>(count).data, '${before - 1}');

    await actAsync(
      tester,
      () => tester.tap(find.byType(FilledButton)),
      settleMs: 200,
    );
    expect(find.byType(SnackBar), findsOneWidget);
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
