import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/pipeline/tokenizer.dart';

void main() {
  group('Tokenizer.forLanguage', () {
    test('builds a tokenizer for a supported language', () {
      expect(Tokenizer.forLanguage('es').languageCode, 'es');
      expect(Tokenizer.forLanguage('fr').languageCode, 'fr');
    });

    test('rejects a language that needs a segmenter instead', () {
      // zh has no whitespace word boundaries, so a whitespace tokenizer
      // would silently emit whole lines as single "words".
      expect(() => Tokenizer.forLanguage('zh'), throwsArgumentError);
    });

    test('reports which languages it supports', () {
      expect(Tokenizer.supports('es'), isTrue);
      expect(Tokenizer.supports('zh'), isFalse);
    });
  });

  group('splitLines', () {
    test('drops blank lines and trims, numbering from zero', () {
      final lines = Tokenizer.forLanguage('es').splitLines('  uno  \n\n dos ');
      expect(lines.map((l) => l.text).toList(), <String>['uno', 'dos']);
      expect(lines.map((l) => l.index).toList(), <int>[0, 1]);
    });
  });

  group('tokenize', () {
    test('lowercases and keeps accented Spanish letters intact', () {
      final tokens = Tokenizer.forLanguage('es').tokenize('Despacito AQUÍ ñu');
      expect(
        tokens.map((t) => t.surface).toList(),
        <String>['despacito', 'aquí', 'ñu'],
      );
    });

    test('strips punctuation but keeps elision as one token', () {
      final tokens = Tokenizer.forLanguage('fr').tokenize("¡Hey! l'amour, oh");
      expect(
        tokens.map((t) => t.surface).toList(),
        <String>['hey', "l'amour", 'oh'],
      );
    });

    test('attaches the originating line to every token', () {
      final tokens = Tokenizer.forLanguage('es').tokenize('uno dos\ntres');
      expect(tokens[0].line.text, 'uno dos');
      expect(tokens[2].line.text, 'tres');
    });
  });

  group('uniqueSurfaces', () {
    test('deduplicates, keeping the first line a word appeared in', () {
      final unique = Tokenizer.forLanguage(
        'es',
      ).uniqueSurfaces('sol luna\nsol mar');
      expect(unique.length, 3);
      expect(unique['sol']!.text, 'sol luna');
    });
  });
}
