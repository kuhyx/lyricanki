import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'flow_harness.dart';

/// What the home screen does when it regains focus from another screen.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lyricanki_nav');
    PathProviderPlatform.instance = FakePathProvider(root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('re-checks the pack after returning from the pack screen', (
    tester,
  ) async {
    // Downloading on the pack screen must unlock the home screen's button
    // without needing a restart.
    final store = storeIn(root);
    await pumpHome(tester, store);
    expect(find.text('No dictionary yet'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.storage_outlined),
      ),
    );
    await tester.pumpAndSettle();

    // Install the pack behind the pack screen, then come back.
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    await actAsync(tester, tester.pageBack);

    expect(find.text('Ready'), findsOneWidget);
    store.close();
  });

  testWidgets('closes the pack after leaving the review screen', (
    tester,
  ) async {
    // The pack holds an open SQLite handle; leaving review without closing it
    // would leak one per deck built.
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final store = storeIn(root);
    await pumpHome(tester, store);
    await pickTrack(tester);
    expect(find.byType(CheckboxListTile), findsWidgets);

    await actAsync(tester, tester.pageBack);
    expect(find.text('Ready'), findsOneWidget);
    store.close();
  });

  testWidgets('can build a second deck after the first, with no stale handle', (
    tester,
  ) async {
    writePack('${root.path}/packs/lyricanki-es.sqlite');
    final store = storeIn(root);
    await pumpHome(tester, store);
    await pickTrack(tester);
    await actAsync(tester, tester.pageBack);
    await pickTrack(tester);
    expect(find.byType(CheckboxListTile), findsWidgets);
    store.close();
  });
}
