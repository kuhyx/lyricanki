import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/export_destination.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Where an exported deck is written.
///
/// The documents directory is the wrong answer on Android and the app shipped
/// with it: `/data/user/0/<pkg>/app_flutter` cannot be read by AnkiDroid, by
/// the storage picker, or by `adb pull` without root, so the export succeeded
/// and was then unreachable by the only app it exists to feed.
void main() {
  group('locations', () {
    test('prefers external storage on Android', () async {
      final external = Directory.systemTemp.createTempSync('ext');
      final documents = Directory.systemTemp.createTempSync('docs');
      PathProviderPlatform.instance = _SplitPathProvider(
        externalPath: external.path,
        documentsPath: documents.path,
      );
      try {
        final dir = await ExportDestination(isAndroid: true).exportDirectory();
        expect(dir.path, startsWith(external.path));
      } finally {
        external.deleteSync(recursive: true);
        documents.deleteSync(recursive: true);
      }
    });

    test('falls back to documents where external storage is absent', () async {
      final documents = Directory.systemTemp.createTempSync('docs');
      PathProviderPlatform.instance = _SplitPathProvider(
        documentsPath: documents.path,
      );
      try {
        final dir = await ExportDestination(isAndroid: true).exportDirectory();
        expect(dir.path, startsWith(documents.path));
      } finally {
        documents.deleteSync(recursive: true);
      }
    });

    test('survives a platform whose external storage throws', () async {
      // Desktop path_provider throws UnimplementedError rather than returning
      // null, so `?? documents` never runs. PackStore was crashing in
      // initState over exactly this before the platform check was added.
      final documents = Directory.systemTemp.createTempSync('docs');
      PathProviderPlatform.instance = _ThrowingExternalPathProvider(
        documentsPath: documents.path,
      );
      try {
        final dir = await ExportDestination(isAndroid: false).exportDirectory();
        expect(dir.path, startsWith(documents.path));
      } finally {
        documents.deleteSync(recursive: true);
      }
    });

    test('creates the directory when it does not exist yet', () async {
      final root = Directory.systemTemp.createTempSync('root');
      try {
        final dir = await ExportDestination(
          directoryOverride: root,
        ).exportDirectory();
        expect(dir.existsSync(), isTrue);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('reuses the directory on a second call', () async {
      // The second call takes the `existsSync` branch rather than creating.
      final root = Directory.systemTemp.createTempSync('root');
      try {
        final destination = ExportDestination(directoryOverride: root);
        final first = await destination.exportDirectory();
        final second = await destination.exportDirectory();
        expect(second.path, first.path);
        expect(second.existsSync(), isTrue);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });

  group('file names', () {
    test('reduces a track title to ASCII word characters', () async {
      // Real titles carry slashes, colons and quotes: a slash would silently
      // become a path separator and the write would fail on a missing parent.
      final root = Directory.systemTemp.createTempSync('root');
      try {
        final path = await ExportDestination(
          directoryOverride: root,
        ).pathFor('Despacito (feat. Daddy Yankee) / Remix: "live"');
        expect(
          path.split(Platform.pathSeparator).last,
          'Despacito_feat_Daddy_Yankee_Remix_live_.apkg',
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('puts the export inside the export directory', () async {
      final root = Directory.systemTemp.createTempSync('root');
      try {
        final destination = ExportDestination(directoryOverride: root);
        final path = await destination.pathFor('Despacito');
        expect(path, startsWith((await destination.exportDirectory()).path));
      } finally {
        root.deleteSync(recursive: true);
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

/// Reports external and documents paths separately, so the preference between
/// them is observable.
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
