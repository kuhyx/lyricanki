import 'package:lyricanki/models/lyric_line.dart';
import 'package:lyricanki/models/token.dart';

/// Splits lyrics into tokens, keeping each token's source line.
///
/// The word pattern is per-language because alphabets differ: Spanish and
/// French need their accented ranges, and a language whose script has no
/// whitespace word boundaries (zh) does not use this class at all -- it goes
/// through a segmenter selected by the pack's `pack_type`.
class Tokenizer {
  /// Creates a tokenizer for [languageCode] using [wordPattern].
  const Tokenizer({required this.languageCode, required this.wordPattern});

  /// Latin-script tokenizer covering the Spanish alphabet.
  ///
  /// The apostrophe branch keeps elided forms (`l'amour`) in one piece rather
  /// than splitting them into a stray `l`.
  factory Tokenizer.forLanguage(String languageCode) {
    final pattern = _patterns[languageCode];
    if (pattern == null) {
      throw ArgumentError.value(
        languageCode,
        'languageCode',
        'no whitespace tokenizer for this language; it needs a segmenter',
      );
    }
    return Tokenizer(languageCode: languageCode, wordPattern: pattern);
  }

  // Character classes are written out rather than built from ranges so the
  // accented letters are visible in review: a missing acute accent silently
  // splits a word in half and inflates the card count.
  static const String _esLetters = 'a-záéíóúüñ';
  static const String _frLetters = 'a-zàâäæçéèêëîïôöœùûüÿ';

  static final Map<String, RegExp> _patterns = <String, RegExp>{
    'es': RegExp(
      '[$_esLetters]+'
      "(?:'[$_esLetters]+)?",
    ),
    'fr': RegExp(
      '[$_frLetters]+'
      "(?:'[$_frLetters]+)?",
    ),
  };

  /// The language this tokenizer is configured for.
  final String languageCode;

  /// The pattern matching one word.
  final RegExp wordPattern;

  /// Whether [languageCode] can be tokenized on whitespace at all.
  static bool supports(String languageCode) =>
      _patterns.containsKey(languageCode);

  /// Splits [lyrics] into lines, dropping blank ones.
  List<LyricLine> splitLines(String lyrics) {
    final lines = <LyricLine>[];
    for (final raw in lyrics.split('\n')) {
      if (raw.trim().isEmpty) {
        continue;
      }
      lines.add(LyricLine(index: lines.length, text: raw.trim()));
    }
    return lines;
  }

  /// Tokenizes [lyrics], returning every occurrence in reading order.
  List<Token> tokenize(String lyrics) {
    final tokens = <Token>[];
    for (final line in splitLines(lyrics)) {
      for (final match in wordPattern.allMatches(line.text.toLowerCase())) {
        tokens.add(Token(surface: match.group(0)!, line: line));
      }
    }
    return tokens;
  }

  /// Maps each distinct surface form to the first line it appeared in.
  ///
  /// First occurrence wins because that is the line a learner meets the word
  /// in; later repeats in a chorus add nothing.
  Map<String, LyricLine> uniqueSurfaces(String lyrics) {
    final seen = <String, LyricLine>{};
    for (final token in tokenize(lyrics)) {
      seen.putIfAbsent(token.surface, () => token.line);
    }
    return seen;
  }
}
