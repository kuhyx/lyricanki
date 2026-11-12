import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A stateful in-memory Realtime Database behind a real [FirebaseRestClient].
///
/// Stateful rather than canned replies because end-to-end encryption writes
/// a header and then reads it back, and the one-time copy reads what an old
/// build left at the plaintext prefix: a fake that forgets its writes cannot
/// exercise either.
class FakeRtdb {
  /// The database tree, keyed by the encoded path segments the client sends.
  final Map<String, Object?> root = <String, Object?>{};

  /// `path -> body` of every PUT and PATCH since the last [clearWrites].
  final List<MapEntry<String, String>> writes = <MapEntry<String, String>>[];

  /// Forgets the recorded writes, keeping the data.
  void clearWrites() => writes.clear();

  /// A client talking to this database.
  FirebaseRestClient client() => FirebaseRestClient(
    databaseUrl: 'https://fake-rtdb.example.com',
    auth: _StubAuth(),
    httpClient: MockClient(_handle),
  );

  List<String> _segments(Uri url) {
    final path = url.path.replaceFirst(RegExp(r'\.json$'), '');
    return path.split('/').where((s) => s.isNotEmpty).toList();
  }

  Map<String, Object?> _parent(List<String> segments, {required bool create}) {
    var node = root;
    for (final segment in segments.take(segments.length - 1)) {
      final child = node[segment];
      if (child is Map<String, Object?>) {
        node = child;
      } else if (create) {
        node = node[segment] = <String, Object?>{};
      } else {
        return <String, Object?>{};
      }
    }
    return node;
  }

  Object? _read(List<String> segments) {
    if (segments.isEmpty) return root;
    return _parent(segments, create: false)[segments.last];
  }

  Future<http.Response> _handle(http.Request request) async {
    final segments = _segments(request.url);
    switch (request.method) {
      case 'GET':
        final value = _read(segments);
        if (request.url.queryParameters['shallow'] == 'true' &&
            value is Map<String, Object?>) {
          return http.Response(
            jsonEncode({for (final key in value.keys) key: true}),
            200,
          );
        }
        return http.Response(jsonEncode(value), 200);
      case 'PUT':
        writes.add(MapEntry(segments.join('/'), request.body));
        _parent(segments, create: true)[segments.last] = jsonDecode(
          request.body,
        );
        return http.Response(request.body, 200);
      case 'PATCH':
        writes.add(MapEntry(segments.join('/'), request.body));
        final parent = _parent(segments, create: true);
        final existing = parent[segments.last];
        parent[segments.last] = <String, Object?>{
          if (existing is Map<String, Object?>) ...existing,
          ...jsonDecode(request.body) as Map<String, Object?>,
        };
        return http.Response(request.body, 200);
      default:
        _parent(segments, create: false).remove(segments.last);
        return http.Response('null', 200);
    }
  }
}

/// A token provider that never reaches the network: the merge, not the
/// sign-in, is what these suites exercise.
class _StubAuth implements FirebaseTokenProvider {
  @override
  Future<String> idToken() async => 'stub-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
