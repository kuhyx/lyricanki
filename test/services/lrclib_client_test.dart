import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/services/lrclib_client.dart';

/// Builds a client whose requests are answered by [handler].
LrclibClient clientReturning(
  Future<http.Response> Function(http.Request request) handler,
) => LrclibClient(httpClient: MockClient(handler));

/// A 200 response carrying [body] as UTF-8 with no charset declared.
///
/// LRCLIB really does omit the charset, which is why the client decodes bytes
/// itself instead of trusting `response.body`.
http.Response utf8Response(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  group('search', () {
    test('parses rows into tracks', () async {
      final client = clientReturning(
        (_) async => utf8Response(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 36856755,
            'trackName': 'Despacito',
            'artistName': 'Luis Fonsi',
            'duration': 273,
            'plainLyrics': 'Ay',
          },
        ]),
      );
      final results = await client.search('Despacito');
      expect(results, hasLength(1));
      expect(results.single.id, 36856755);
      client.close();
    });

    test('sends q and identifies the app', () async {
      Uri? seenUri;
      String? seenAgent;
      final client = clientReturning((request) async {
        seenUri = request.url;
        seenAgent = request.headers['User-Agent'];
        return utf8Response(<Map<String, dynamic>>[]);
      });
      await client.search('Despacito');
      expect(seenUri!.queryParameters['q'], 'Despacito');
      expect(seenAgent, LrclibClient.userAgent);
      expect(seenAgent, contains('lyricanki'));
      client.close();
    });

    test('decodes accents from bytes rather than latin-1', () async {
      final client = clientReturning(
        (_) async => utf8Response(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'trackName': 'Corazón',
            'artistName': 'Fonsi',
            'duration': 1,
            'plainLyrics': '¡Fonsi!',
          },
        ]),
      );
      final results = await client.search('x');
      expect(results.single.name, 'Corazón');
      expect(results.single.plainLyrics, '¡Fonsi!');
      client.close();
    });

    test('throws when the payload is not a list', () async {
      final client = clientReturning(
        (_) async => utf8Response(<String, dynamic>{'oops': true}),
      );
      await expectLater(
        client.search('x'),
        throwsA(isA<LrclibException>()),
      );
      client.close();
    });
  });

  group('getById', () {
    test('returns the pinned track', () async {
      final client = clientReturning(
        (_) async => utf8Response(<String, dynamic>{
          'id': 36856755,
          'trackName': 'Despacito',
          'artistName': 'Luis Fonsi',
          'duration': 273,
          'plainLyrics': 'Ay',
        }),
      );
      final track = await client.getById(36856755);
      expect(track.id, 36856755);
      client.close();
    });

    test('throws when the payload is not an object', () async {
      final client = clientReturning(
        (_) async => utf8Response(<int>[1, 2]),
      );
      await expectLater(
        client.getById(1),
        throwsA(isA<LrclibException>()),
      );
      client.close();
    });
  });

  group('errors', () {
    test('reports 404 as missing lyrics', () async {
      final client = clientReturning((_) async => http.Response('', 404));
      await expectLater(
        client.getById(1),
        throwsA(
          isA<LrclibException>().having(
            (e) => e.message,
            'message',
            contains('no lyrics'),
          ),
        ),
      );
      client.close();
    });

    test('reports other statuses with the code', () async {
      final client = clientReturning((_) async => http.Response('', 503));
      await expectLater(
        client.getById(1),
        throwsA(
          isA<LrclibException>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
      client.close();
    });

    test('reports malformed JSON', () async {
      final client = clientReturning(
        (_) async => http.Response.bytes(utf8.encode('{not json'), 200),
      );
      await expectLater(
        client.search('x'),
        throwsA(
          isA<LrclibException>().having(
            (e) => e.message,
            'message',
            contains('malformed'),
          ),
        ),
      );
      client.close();
    });

    test('reports an unreachable host', () async {
      final client = clientReturning((_) async => throw const SocketLike());
      await expectLater(
        client.search('x'),
        throwsA(
          isA<LrclibException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach'),
          ),
        ),
      );
      client.close();
    });

    test('has a readable toString', () {
      expect(
        const LrclibException('boom').toString(),
        'LrclibException: boom',
      );
    });
  });
}

/// Stands in for a network failure without depending on dart:io in a test.
class SocketLike implements Exception {
  const SocketLike();
  @override
  String toString() => 'SocketLike';
}
