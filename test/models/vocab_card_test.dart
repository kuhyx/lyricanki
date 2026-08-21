import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/models/vocab_card.dart';

void main() {
  const base = VocabCard(
    lemma: 'corazón',
    pos: 'noun',
    gloss: 'heart',
    line: 'Despacito',
  );

  group('value equality', () {
    test('equal when every field matches', () {
      const same = VocabCard(
        lemma: 'corazón',
        pos: 'noun',
        gloss: 'heart',
        line: 'Despacito',
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
    });

    test('differs on lemma', () {
      const other = VocabCard(
        lemma: 'amor',
        pos: 'noun',
        gloss: 'heart',
        line: 'Despacito',
      );
      expect(base, isNot(other));
    });

    test('differs on pos', () {
      const other = VocabCard(
        lemma: 'corazón',
        pos: 'verb',
        gloss: 'heart',
        line: 'Despacito',
      );
      expect(base, isNot(other));
    });

    test('differs on gloss', () {
      const other = VocabCard(
        lemma: 'corazón',
        pos: 'noun',
        gloss: 'core',
        line: 'Despacito',
      );
      expect(base, isNot(other));
    });

    test('differs on line, so a re-met word carries its newest context', () {
      const other = VocabCard(
        lemma: 'corazón',
        pos: 'noun',
        gloss: 'heart',
        line: 'Otra canción',
      );
      expect(base, isNot(other));
    });

    test('is not equal to a different type', () {
      expect(base, isNot(equals('corazón')));
    });
  });

  group('toString', () {
    test('names the lemma and part of speech', () {
      expect(base.toString(), 'VocabCard(corazón, noun)');
    });
  });

  group('isExportable', () {
    test('accepts a genuine gloss', () {
      expect(base.isExportable, isTrue);
    });

    test('rejects an empty gloss', () {
      const card = VocabCard(lemma: 'x', pos: 'noun', gloss: '', line: 'y');
      expect(card.isExportable, isFalse);
    });

    test('rejects a whitespace-only gloss', () {
      const card = VocabCard(lemma: 'x', pos: 'noun', gloss: ' \t ', line: 'y');
      expect(card.isExportable, isFalse);
    });

    test('rejects a gloss that is only punctuation', () {
      const card = VocabCard(lemma: 'x', pos: 'noun', gloss: '...', line: 'y');
      expect(card.isExportable, isFalse);
    });

    test('rejects a gloss identical to the word', () {
      const card = VocabCard(
        lemma: 'corazón',
        pos: 'noun',
        gloss: 'corazón',
        line: 'y',
      );
      expect(card.isExportable, isFalse);
    });

    test('rejects the real defect shape: capitalised and full-stopped', () {
      // This is the card that actually shipped once: the per-language extract
      // defines Spanish words in Spanish, so corazón was glossed "Corazón.".
      const card = VocabCard(
        lemma: 'corazón',
        pos: 'noun',
        gloss: 'Corazón.',
        line: 'y',
      );
      expect(card.isExportable, isFalse);
    });

    test('rejects a gloss wrapped in Spanish punctuation', () {
      const card = VocabCard(
        lemma: 'qué',
        pos: 'pron',
        gloss: '¿Qué?',
        line: 'y',
      );
      expect(card.isExportable, isFalse);
    });

    test('keeps a gloss that merely contains the word', () {
      // "heart; core of the corazón" is odd but genuinely informative -- only
      // an exact match after normalisation is a defect.
      const card = VocabCard(
        lemma: 'corazón',
        pos: 'noun',
        gloss: 'heart, corazón in Spanish',
        line: 'y',
      );
      expect(card.isExportable, isTrue);
    });
  });
}
