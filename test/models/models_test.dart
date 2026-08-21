import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/lyric_line.dart';
import 'package:lyricanki/models/token.dart';

void main() {
  const line = LyricLine(index: 0, text: 'Despacito');
  const other = LyricLine(index: 1, text: 'Despacito');

  group('LyricLine', () {
    test('compares by index and text', () {
      expect(line, const LyricLine(index: 0, text: 'Despacito'));
      expect(line, isNot(other));
      expect(
        line.hashCode,
        const LyricLine(index: 0, text: 'Despacito').hashCode,
      );
    });

    test('is not equal to a different type', () {
      expect(line == Object(), isFalse);
    });

    test('describes itself for test failures', () {
      expect(line.toString(), 'LyricLine(0, Despacito)');
    });
  });

  group('Token', () {
    const token = Token(surface: 'despacito', line: line);

    test('compares by surface and line', () {
      expect(token, const Token(surface: 'despacito', line: line));
      expect(token, isNot(const Token(surface: 'suave', line: line)));
      expect(token, isNot(const Token(surface: 'despacito', line: other)));
      expect(
        token.hashCode,
        const Token(surface: 'despacito', line: line).hashCode,
      );
    });

    test('is not equal to a different type', () {
      expect(token == Object(), isFalse);
    });

    test('describes itself for test failures', () {
      expect(token.toString(), 'Token(despacito)');
    });
  });
}
