import 'package:lyricanki/models/lyric_line.dart';
import 'package:meta/meta.dart';

/// One surface form as it occurred in the lyrics, with the line it came from.
@immutable
class Token {
  /// Creates a token.
  const Token({required this.surface, required this.line});

  /// The lowercased surface form, e.g. `vamos`.
  final String surface;

  /// The lyric line this token was found in.
  final LyricLine line;

  @override
  bool operator ==(Object other) =>
      other is Token && other.surface == surface && other.line == line;

  @override
  int get hashCode => Object.hash(surface, line);

  @override
  String toString() => 'Token($surface)';
}
