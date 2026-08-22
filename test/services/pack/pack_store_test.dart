import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/services/pack/pack_store.dart';

/// Streams [body] as a 200, optionally declaring a content length.
MockClient streaming(List<int> body, {bool withLength = true}) =>
    MockClient.streaming((request, _) async {
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[body]),
        200,
        contentLength: withLength ? body.length : null,
      );
    });

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('lyricanki_store'));
  tearDown(() => root.deleteSync(recursive: true));

  PackStore storeWith(http.Client client) =>
      PackStore(httpClient: client, directoryOverride: root);

  group('construction', () {
    test('creates its own HTTP client when none is injected', () {
      // The app constructs it this way; only tests pass a client.
      PackStore().close();
    });
  });

  group('locations', () {
    test('creates the pack directory on first use', () async {
      final store = storeWith(MockClient((_) async => http.Response('', 200)));
      final dir = await store.packDirectory();
      expect(dir.existsSync(), isTrue);
      expect(dir.path, contains('packs'));
      store.close();
    });

    test('names a pack after its language', () async {
      final store = storeWith(MockClient((_) async => http.Response('', 200)));
      final file = await store.packFile('es');
      expect(file.path, endsWith('lyricanki-es.sqlite'));
      store.close();
    });
  });

  group('hasPack', () {
    test('is false when nothing is downloaded', () async {
      final store = storeWith(MockClient((_) async => http.Response('', 200)));
      expect(await store.hasPack('es'), isFalse);
      store.close();
    });

    test('is true once a non-empty pack exists', () async {
      final store = storeWith(streaming(utf8.encode('SQLite format 3')));
      await store.download('es');
      expect(await store.hasPack('es'), isTrue);
      store.close();
    });

    test('treats a zero-byte file as absent, not as a usable pack', () async {
      // An interrupted download leaves one behind; calling it present would
      // fail later with a confusing SQLite error.
      final store = storeWith(MockClient((_) async => http.Response('', 200)));
      (await store.packFile('es')).createSync(recursive: true);
      expect(await store.hasPack('es'), isFalse);
      store.close();
    });
  });

  group('installedLanguages', () {
    test('is empty before anything is downloaded', () async {
      final store = storeWith(MockClient((_) async => http.Response('', 200)));
      expect(await store.installedLanguages(), isEmpty);
      store.close();
    });

    test('lists downloaded packs in order', () async {
      final store = storeWith(streaming(utf8.encode('data')));
      await store.download('fr');
      await store.download('es');
      expect(await store.installedLanguages(), <String>['es', 'fr']);
      store.close();
    });

    test('ignores files that are not packs', () async {
      final store = storeWith(MockClient((_) async => http.Response('', 200)));
      final dir = await store.packDirectory();
      File('${dir.path}/notes.txt').writeAsStringSync('x');
      Directory('${dir.path}/sub').createSync();
      expect(await store.installedLanguages(), isEmpty);
      store.close();
    });
  });

  group('download', () {
    test('writes the pack and reports progress', () async {
      final store = storeWith(streaming(utf8.encode('0123456789')));
      final seen = <double?>[];
      final file = await store.download('es', onProgress: seen.add);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), '0123456789');
      expect(seen.last, 1.0);
      store.close();
    });

    test('reports null progress when the size is unknown', () async {
      final store = storeWith(
        streaming(utf8.encode('data'), withLength: false),
      );
      final seen = <double?>[];
      await store.download('es', onProgress: seen.add);
      expect(seen, everyElement(isNull));
      store.close();
    });

    test('leaves no .part file behind on success', () async {
      final store = storeWith(streaming(utf8.encode('data')));
      await store.download('es');
      final dir = await store.packDirectory();
      expect(
        dir.listSync().map((e) => e.path).where((p) => p.endsWith('.part')),
        isEmpty,
      );
      store.close();
    });

    test('replaces an existing pack rather than failing', () async {
      final store = storeWith(streaming(utf8.encode('newer')));
      final target = await store.packFile('es');
      target.writeAsStringSync('older');
      await store.download('es');
      expect(target.readAsStringSync(), 'newer');
      store.close();
    });

    test('throws on a non-200 and installs nothing', () async {
      final store = PackStore(
        httpClient: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            const Stream<List<int>>.empty(),
            404,
          ),
        ),
        directoryOverride: root,
      );
      await expectLater(
        store.download('es'),
        throwsA(isA<PackDownloadException>()),
      );
      expect(await store.hasPack('es'), isFalse);
      store.close();
    });

    test('rejects an empty body rather than installing a dead pack', () async {
      final store = storeWith(streaming(<int>[]));
      await expectLater(
        store.download('es'),
        throwsA(
          isA<PackDownloadException>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );
      expect(await store.hasPack('es'), isFalse);
      store.close();
    });

    test('honours a source override, for a pack served elsewhere', () async {
      Uri? seen;
      final store = PackStore(
        httpClient: MockClient.streaming((request, _) async {
          seen = request.url;
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[utf8.encode('x')]),
            200,
            contentLength: 1,
          );
        }),
        directoryOverride: root,
      );
      await store.download(
        'es',
        sourceOverride: Uri.parse('https://example.test/pack.sqlite'),
      );
      expect(seen.toString(), 'https://example.test/pack.sqlite');
      store.close();
    });

    test('defaults to the public release asset', () async {
      Uri? seen;
      final store = PackStore(
        httpClient: MockClient.streaming((request, _) async {
          seen = request.url;
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[utf8.encode('x')]),
            200,
            contentLength: 1,
          );
        }),
        directoryOverride: root,
      );
      await store.download('es');
      expect(seen.toString(), '${PackStore.releaseBase}/lyricanki-es.sqlite');
      store.close();
    });
  });

  group('delete', () {
    test('removes an installed pack', () async {
      final store = storeWith(streaming(utf8.encode('data')));
      await store.download('es');
      await store.delete('es');
      expect(await store.hasPack('es'), isFalse);
      store.close();
    });

    test('is a no-op when the pack is absent', () async {
      final store = storeWith(MockClient((_) async => http.Response('', 200)));
      await store.delete('es');
      expect(await store.hasPack('es'), isFalse);
      store.close();
    });
  });

  group('PackDownloadException', () {
    test('has a readable toString', () {
      expect(
        const PackDownloadException('boom').toString(),
        'PackDownloadException: boom',
      );
    });
  });
}
