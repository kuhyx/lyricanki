import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/services/pack/pack_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Where PackStore decides to keep packs.
///
/// Split from `pack_store_test.dart` to hold the 250-line cap.
void main() {
  group('locations', () {
    test('prefers external storage, which adb can push into', () async {
      // On Android this resolves to /sdcard/Android/data/<pkg>/files, which
      // `adb push` can write and the app can read with no permission. The
      // documents directory lives under /data/data and adb cannot write there
      // without root, so preferring it would make side-loading a 43 MB pack
      // impossible.
      final external = Directory.systemTemp.createTempSync('ext');
      final documents = Directory.systemTemp.createTempSync('docs');
      PathProviderPlatform.instance = _SplitPathProvider(
        externalPath: external.path,
        documentsPath: documents.path,
      );
      final store = PackStore(
        httpClient: MockClient((_) async => http.Response('', 200)),
        isAndroid: true,
      );
      try {
        expect((await store.packDirectory()).path, startsWith(external.path));
      } finally {
        store.close();
        external.deleteSync(recursive: true);
        documents.deleteSync(recursive: true);
      }
    });

    test(
      'falls back to documents where there is no external storage',
      () async {
        final documents = Directory.systemTemp.createTempSync('docs');
        PathProviderPlatform.instance = _SplitPathProvider(
          documentsPath: documents.path,
        );
        final store = PackStore(
          httpClient: MockClient((_) async => http.Response('', 200)),
          isAndroid: true,
        );
        try {
          expect(
            (await store.packDirectory()).path,
            startsWith(documents.path),
          );
        } finally {
          store.close();
          documents.deleteSync(recursive: true);
        }
      },
    );

    test('survives a platform whose external storage throws', () async {
      // The desktop path_provider does not return null for external storage,
      // it throws UnimplementedError. A `?? documents` fallback therefore
      // never runs, and the app crashed in initState before its first frame.
      // The mock above returns null, which is why this went unnoticed until
      // the app was run on Linux.
      final documents = Directory.systemTemp.createTempSync('docs');
      PathProviderPlatform.instance = _ThrowingExternalPathProvider(
        documentsPath: documents.path,
      );
      final store = PackStore(
        httpClient: MockClient((_) async => http.Response('', 200)),
        isAndroid: false,
      );
      try {
        expect((await store.packDirectory()).path, startsWith(documents.path));
      } finally {
        store.close();
        documents.deleteSync(recursive: true);
      }
    });
  });
}

/// Throws from external storage the way the real desktop implementation does.
class _ThrowingExternalPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _ThrowingExternalPathProvider({required this.documentsPath});

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String?> getExternalStoragePath() async =>
      throw UnimplementedError('getExternalStoragePath() is Android-only.');
}

/// Reports external and documents paths separately, so the store's preference
/// between them is observable.
class _SplitPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SplitPathProvider({required this.documentsPath, this.externalPath});

  final String documentsPath;
  final String? externalPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String?> getExternalStoragePath() async => externalPath;
}
