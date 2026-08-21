import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lyricanki/models/track.dart';

/// Thrown when LRCLIB cannot be reached or answers with an error.
class LrclibException implements Exception {
  /// Creates the exception.
  const LrclibException(this.message);

  /// Human-readable cause, shown in the UI.
  final String message;

  @override
  String toString() => 'LrclibException: $message';
}

/// Read-only client for the LRCLIB lyrics API.
///
/// No API key. LRCLIB asks clients to identify themselves, and a generic agent
/// risks being blocked, so [userAgent] is sent on every request and names the
/// app and its repository.
class LrclibClient {
  /// Creates a client, optionally over an injected [httpClient] for tests.
  LrclibClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Base URL of the public instance.
  static const String baseUrl = 'https://lrclib.net';

  /// Identifies this app to LRCLIB, as their docs request.
  static const String userAgent =
      'lyricanki v1.0 (https://github.com/kuhyx/lyricanki)';

  /// Searches tracks matching [query].
  ///
  /// Returns every match rather than guessing: a bare "Despacito" search
  /// yields ~20 rows including the Bieber remix, whose English verses would
  /// poison a Spanish deck. Choosing between them is the user's job (Q3), so
  /// the picker shows artist and duration to tell versions apart.
  Future<List<Track>> search(String query) async {
    final uri = Uri.parse('$baseUrl/api/search').replace(
      queryParameters: <String, String>{'q': query},
    );
    final body = await _getJson(uri);
    if (body is! List) {
      throw const LrclibException('Unexpected search response from LRCLIB.');
    }
    return body.whereType<Map<String, dynamic>>().map(Track.fromJson).toList();
  }

  /// Fetches one track by its LRCLIB [id].
  Future<Track> getById(int id) async {
    final body = await _getJson(Uri.parse('$baseUrl/api/get/$id'));
    if (body is! Map<String, dynamic>) {
      throw const LrclibException('Unexpected track response from LRCLIB.');
    }
    return Track.fromJson(body);
  }

  Future<Object?> _getJson(Uri uri) async {
    http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: <String, String>{'User-Agent': userAgent},
      );
    } on Exception catch (error) {
      throw LrclibException('Could not reach LRCLIB: $error');
    }
    if (response.statusCode == 404) {
      throw const LrclibException('LRCLIB has no lyrics for that track.');
    }
    if (response.statusCode != 200) {
      throw LrclibException('LRCLIB returned HTTP ${response.statusCode}.');
    }
    try {
      // Decode from bytes, not response.body: LRCLIB omits the charset on some
      // responses, and http then falls back to latin-1, which mangles every
      // accented Spanish word into mojibake.
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw LrclibException('LRCLIB sent malformed JSON: ${error.message}');
    }
  }

  /// Releases the underlying HTTP client.
  void close() => _http.close();
}
