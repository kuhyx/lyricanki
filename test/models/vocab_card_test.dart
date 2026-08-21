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

    test('keeps a homograph whose gloss matches the word', () {
      // `me` really is glossed "me" and `metal` really is glossed "metal".
      // These are correct translations that happen to be spelled alike, and
      // dropping them would lose two real words from the pinned song. The
      // Spanish-defined-in-Spanish defect is excluded at pack build time, not
      // here, so an identical gloss reaching this point is genuine.
      const me = VocabCard(lemma: 'me', pos: 'pron', gloss: 'me', line: 'y');
      const metal = VocabCard(
        lemma: 'metal',
        pos: 'noun',
        gloss: 'metal',
        line: 'y',
      );
      expect(me.isExportable, isTrue);
      expect(metal.isExportable, isTrue);
    });

    test('keeps a gloss that merely contains the word', () {
      const card = VocabCard(
        lemma: 'corazón',
        pos: 'noun',
        gloss: 'heart, corazón in Spanish',
        line: 'y',
      );
      expect(card.isExportable, isTrue);
    });
  });

  group('mergedWith', () {
    test('joins parts of speech and glosses, keeping the first line', () {
      const det = VocabCard(
        lemma: 'tu',
        pos: 'det',
        gloss: 'apocopic form of tuyo',
        line: 'Tu cuerpo',
      );
      const adj = VocabCard(
        lemma: 'tu',
        pos: 'adj',
        gloss: 'your',
        line: 'Otra línea',
      );
      final merged = det.mergedWith(adj);
      expect(merged.lemma, 'tu');
      expect(merged.pos, 'det/adj');
      expect(merged.gloss, 'apocopic form of tuyo; your');
      // The context line stays the first occurrence.
      expect(merged.line, 'Tu cuerpo');
    });

    test('de-duplicates identical readings rather than repeating them', () {
      const a = VocabCard(lemma: 'tu', pos: 'det', gloss: 'your', line: 'l');
      const b = VocabCard(lemma: 'tu', pos: 'det', gloss: 'Your', line: 'm');
      final merged = a.mergedWith(b);
      expect(merged.pos, 'det');
      expect(merged.gloss, 'your');
    });

    test('drops a blank reading instead of leaving a dangling separator', () {
      const a = VocabCard(lemma: 'x', pos: 'noun', gloss: 'thing', line: 'l');
      const b = VocabCard(lemma: 'x', pos: '', gloss: '', line: 'm');
      final merged = a.mergedWith(b);
      expect(merged.pos, 'noun');
      expect(merged.gloss, 'thing');
    });

    test('stays exportable after merging', () {
      const a = VocabCard(lemma: 'tu', pos: 'det', gloss: 'your', line: 'l');
      const b = VocabCard(lemma: 'tu', pos: 'adj', gloss: 'your', line: 'm');
      expect(a.mergedWith(b).isExportable, isTrue);
    });
  });
}
