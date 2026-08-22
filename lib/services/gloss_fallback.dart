import 'dart:convert';

import 'package:http/http.dart' as http;

/// One gloss recovered online.
typedef FallbackGloss = ({String lemma, String pos, String gloss});

/// Looks up words the pack does not have, using English Wiktionary.
///
/// **The pack stays the source of truth.** This is a fallback for genuine
/// misses only: it was measured at 95% coverage against the pack's 96%, and it
/// costs a network round trip per word, so calling it for words the pack
/// already knows would be slower and *less* accurate.
///
/// Wikimedia's API policy is followed deliberately: a unique contactable
/// User-Agent (generic ones "may be blocked"), and results cached in memory so
/// a word is fetched at most once per session. Returned content is CC BY-SA
/// 3.0 and GFDL, which the attribution screen credits.
class GlossFallback {
  /// Creates a fallback client.
  GlossFallback({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Map<String, FallbackGloss?> _cache = <String, FallbackGloss?>{};

  /// Identifies this app to Wikimedia, as their policy requires.
  static const String userAgent =
      'lyricanki/1.0 (https://github.com/kuhyx/lyricanki)';

  /// Endpoint template. English Wiktionary defines Spanish words *in English*,
  /// which is exactly what a card back needs — the Spanish Wiktionary defines
  /// them in Spanish and is useless here.
  static const String baseUrl =
      'https://en.wiktionary.org/api/rest_v1/page/definition';

  /// Number of words looked up this session, for reporting to the user.
  int get lookupCount => _cache.length;

  /// Returns a gloss for [surface] in [language], or `null`.
  ///
  /// Inflected forms return only a *pointer* on Wiktionary — `está` yields
  /// "inflection of estar" with no definition — so a form-of response is
  /// followed once to its lemma. The hop is capped at one: a pointer chain
  /// longer than that means the entry is not usable as a card back.
  Future<FallbackGloss?> lookup(
    String surface, {
    String language = 'es',
  }) async {
    if (_cache.containsKey(surface)) return _cache[surface];
    final result = await _lookupUncached(surface, language);
    _cache[surface] = result;
    return result;
  }

  Future<FallbackGloss?> _lookupUncached(
    String surface,
    String language,
  ) async {
    final direct = await _fetch(surface, language);
    if (direct == null) return null;
    if (direct.gloss.isNotEmpty) return direct;

    // Form-of entry: follow the pointer once to the lemma it names.
    final target = direct.lemma;
    if (target.isEmpty || target == surface) return null;
    final resolved = await _fetch(target, language);
    if (resolved == null || resolved.gloss.isEmpty) return null;
    return (lemma: target, pos: resolved.pos, gloss: resolved.gloss);
  }

  /// Fetches one page. Returns a record whose `gloss` is empty and whose
  /// `lemma` names the target when the entry is only a form-of pointer.
  Future<FallbackGloss?> _fetch(String word, String language) async {
    final uri = Uri.parse('$baseUrl/${Uri.encodeComponent(word)}');
    http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: <String, String>{'User-Agent': userAgent},
      );
    } on Exception {
      // Offline is not an error here: the pack is the source of truth and the
      // fallback is best-effort, so a failure just means no extra card.
      return null;
    }
    if (response.statusCode != 200) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final entries = decoded[language];
    if (entries is! List) return null;

    for (final entry in entries.whereType<Map<String, dynamic>>()) {
      final pos = (entry['partOfSpeech'] as String?) ?? '';
      final definitions = entry['definitions'];
      if (definitions is! List) continue;
      for (final def in definitions.whereType<Map<String, dynamic>>()) {
        final text = stripHtml((def['definition'] as String?) ?? '');
        if (text.isEmpty) continue;
        final pointer = formOfTarget((def['definition'] as String?) ?? '');
        if (pointer != null) {
          return (lemma: pointer, pos: pos.toLowerCase(), gloss: '');
        }
        return (lemma: word, pos: pos.toLowerCase(), gloss: text);
      }
    }
    return null;
  }

  /// Releases the underlying HTTP client.
  void close() => _http.close();
}

/// Strips HTML tags and collapses whitespace in a Wiktionary definition.
String stripHtml(String html) => html
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Returns the lemma a form-of definition points at, or `null`.
///
/// Wiktionary marks these with a `form-of-definition-link` span wrapping a
/// `/wiki/<lemma>#Spanish` href, which is what is matched here rather than the
/// prose, since the wording varies ("inflection of", "second-person singular
/// imperative of", ...).
String? formOfTarget(String html) {
  if (!html.contains('form-of-definition')) return null;
  final match = RegExp('/wiki/([^#"]+)#').firstMatch(html);
  if (match == null) return null;
  return Uri.decodeComponent(match.group(1)!);
}
