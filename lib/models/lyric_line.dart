import 'package:meta/meta.dart';

/// A single line of lyrics, kept so every card can show the context the word
/// was sung in (Q4: the source lyric line is always attached).
@immutable
class LyricLine {
  /// Creates a lyric line.
  const LyricLine({required this.index, required this.text});

  /// Zero-based position of the line within the song.
  final int index;

  /// The line as it appears in the lyrics.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.index == index && other.text == text;

  @override
  int get hashCode => Object.hash(index, text);

  @override
  String toString() => 'LyricLine($index, $text)';
}
