import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyricanki/services/gloss_fallback.dart';

/// A Wiktionary definition payload for [language].
Map<String, dynamic> page(
  String language,
  String pos,
  List<String> definitions,
) => <String, dynamic>{
  language: <Map<String, dynamic>>[
    <String, dynamic>{
      'partOfSpeech': pos,
      'definitions': <Map<String, dynamic>>[
        for (final d in definitions) <String, dynamic>{'definition': d},
      ],
    },
  ],
};

http.Response ok(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

void main() {
  group('construction', () {
    test('creates its own HTTP client when none is injected', () {
      // The app constructs it this way; only tests pass a client.
      GlossFallback().close();
    });
  });

  group('lookup', () {
    test('returns a direct English gloss for a Spanish word', () async {
      final fb = GlossFallback(
        httpClient: MockClient(
          (_) async => ok(page('es', 'Noun', <String>['heart'])),
        ),
      );
      final got = await fb.lookup('corazón');
      expect(got!.lemma, 'corazón');
      expect(got.pos, 'noun');
      expect(got.gloss, 'heart');
      fb.close();
    });

    test('follows a form-of pointer to the lemma', () async {
      // `está` yields only "inflection of estar" -- no gloss -- so the client
      // has to hop once to be useful at all.
      final fb = GlossFallback(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('est%C3%A1')) {
            return ok(
              page('es', 'Verb', <String>[
                '<span class="form-of-definition">inflection of '
                    '<a href="/wiki/estar#Spanish">estar</a></span>',
              ]),
            );
          }
          return ok(page('es', 'Verb', <String>['to be']));
        }),
      );
      final got = await fb.lookup('está');
      expect(got!.lemma, 'estar');
      expect(got.gloss, 'to be');
      fb.close();
    });

    test('stops after one hop rather than chasing a pointer chain', () async {
      var calls = 0;
      final fb = GlossFallback(
        httpClient: MockClient((_) async {
          calls++;
          return ok(
            page('es', 'Verb', <String>[
              '<span class="form-of-definition">inflection of '
                  '<a href="/wiki/other#Spanish">other</a></span>',
            ]),
          );
        }),
      );
      expect(await fb.lookup('x'), isNull);
      expect(calls, 2);
      fb.close();
    });

    test(
      'caches, so a word costs at most one round trip per session',
      () async {
        var calls = 0;
        final fb = GlossFallback(
          httpClient: MockClient((_) async {
            calls++;
            return ok(page('es', 'Noun', <String>['heart']));
          }),
        );
        await fb.lookup('corazón');
        await fb.lookup('corazón');
        expect(calls, 1);
        expect(fb.lookupCount, 1);
        fb.close();
      },
    );

    test('caches misses too, so a dead word is not re-fetched', () async {
      var calls = 0;
      final fb = GlossFallback(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('', 404);
        }),
      );
      expect(await fb.lookup('dididiri'), isNull);
      expect(await fb.lookup('dididiri'), isNull);
      expect(calls, 1);
      fb.close();
    });

    test(
      'sends a contactable User-Agent, as Wikimedia policy requires',
      () async {
        String? agent;
        final fb = GlossFallback(
          httpClient: MockClient((request) async {
            agent = request.headers['User-Agent'];
            return ok(page('es', 'Noun', <String>['heart']));
          }),
        );
        await fb.lookup('corazón');
        expect(agent, GlossFallback.userAgent);
        expect(agent, contains('lyricanki'));
        fb.close();
      },
    );

    test(
      'returns null when the word has no section for the language',
      () async {
        final fb = GlossFallback(
          httpClient: MockClient(
            (_) async => ok(page('en', 'Noun', <String>['a thing'])),
          ),
        );
        expect(await fb.lookup('bang'), isNull);
        fb.close();
      },
    );

    test('returns null on a non-200, without throwing', () async {
      final fb = GlossFallback(
        httpClient: MockClient((_) async => http.Response('', 500)),
      );
      expect(await fb.lookup('x'), isNull);
      fb.close();
    });

    test('returns null on malformed JSON', () async {
      final fb = GlossFallback(
        httpClient: MockClient(
          (_) async => http.Response.bytes(utf8.encode('{nope'), 200),
        ),
      );
      expect(await fb.lookup('x'), isNull);
      fb.close();
    });

    test('treats being offline as a miss, not an error', () async {
      // The pack is the source of truth; a network failure just means no
      // extra card, so this must never throw into the export flow.
      final fb = GlossFallback(
        httpClient: MockClient((_) async => throw const _Offline()),
      );
      expect(await fb.lookup('x'), isNull);
      fb.close();
    });

    test('skips a definition that is only markup', () async {
      final fb = GlossFallback(
        httpClient: MockClient(
          (_) async =>
              ok(page('es', 'Noun', <String>['<span></span>', 'heart'])),
        ),
      );
      expect((await fb.lookup('corazón'))!.gloss, 'heart');
      fb.close();
    });

    test('ignores an entry whose definitions are not a list', () async {
      final fb = GlossFallback(
        httpClient: MockClient(
          (_) async => ok(<String, dynamic>{
            'es': <Map<String, dynamic>>[
              <String, dynamic>{'partOfSpeech': 'Noun', 'definitions': 'oops'},
            ],
          }),
        ),
      );
      expect(await fb.lookup('x'), isNull);
      fb.close();
    });

    test('ignores a payload that is not an object', () async {
      final fb = GlossFallback(
        httpClient: MockClient((_) async => ok(<int>[1, 2])),
      );
      expect(await fb.lookup('x'), isNull);
      fb.close();
    });

    test('ignores a language key that is not a list', () async {
      final fb = GlossFallback(
        httpClient: MockClient(
          (_) async => ok(<String, dynamic>{'es': 'oops'}),
        ),
      );
      expect(await fb.lookup('x'), isNull);
      fb.close();
    });

    test('refuses a pointer back to the word itself', () async {
      final fb = GlossFallback(
        httpClient: MockClient(
          (_) async => ok(
            page('es', 'Verb', <String>[
              '<span class="form-of-definition">'
                  '<a href="/wiki/x#Spanish">x</a></span>',
            ]),
          ),
        ),
      );
      expect(await fb.lookup('x'), isNull);
      fb.close();
    });
  });
}

class _Offline implements Exception {
  const _Offline();
}
