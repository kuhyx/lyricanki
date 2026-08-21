import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/pack/enclitics.dart';

typedef Row = ({String lemma, String pos});

Row row(String lemma, String pos) => (lemma: lemma, pos: pos);

void main() {
  group('splitEnclitics', () {
    test('splits a double-pronoun cluster', () {
      expect(splitEnclitics('dámelo'), contains('dá'));
    });

    test('offers the unaccented stem, since the accent is only there for the '
        'cluster', () {
      expect(splitEnclitics('dámelo'), contains('da'));
      expect(splitEnclitics('quítate'), contains('quita'));
    });

    test('splits a single pronoun', () {
      expect(splitEnclitics('déjame'), contains('déja'));
    });

    test('yields nothing when the word does not end in a pronoun', () {
      expect(splitEnclitics('corazón'), isEmpty);
    });

    test('refuses to split when the pronoun is the whole word', () {
      expect(splitEnclitics('me'), isEmpty);
      expect(splitEnclitics('lo'), isEmpty);
    });

    test('tries longer pronouns first so nos beats os', () {
      final stems = splitEnclitics('vamonos').toList();
      expect(stems.first, 'vamo');
    });
  });

  group('resolveEnclitic', () {
    test('resolves dámelo to the verb dar', () {
      final got = resolveEnclitic(
        'dámelo',
        (stem) => stem == 'da' ? <Row>[row('dar', 'verb')] : <Row>[],
      );
      expect(got, row('dar', 'verb'));
    });

    test('refuses the proper-noun reading rather than carding it', () {
      // `dámelo` also matches the name "Dame". Only verbs take enclitic
      // pronouns, so the noun is not merely less likely -- it is wrong, and
      // carding it would pass a "gloss is non-empty" check while teaching
      // the learner a name that is not in the song.
      final got = resolveEnclitic(
        'dámelo',
        (stem) => <Row>[row('Dame', 'name')],
      );
      expect(got, isNull);
    });

    test('picks the verb when a stem matches both a verb and a noun', () {
      final got = resolveEnclitic(
        'quítate',
        (stem) => <Row>[row('Quita', 'name'), row('quitar', 'verb')],
      );
      expect(got, row('quitar', 'verb'));
    });

    test('returns null when nothing matches', () {
      expect(resolveEnclitic('dámelo', (_) => <Row>[]), isNull);
    });

    test('returns null for a word with no enclitic ending', () {
      expect(
        resolveEnclitic('corazón', (_) => <Row>[row('x', 'verb')]),
        isNull,
      );
    });
  });

  group('encliticPronouns', () {
    test('lists longer pronouns before their own suffixes', () {
      expect(
        encliticPronouns.indexOf('melo'),
        lessThan(encliticPronouns.indexOf('lo')),
      );
      expect(
        encliticPronouns.indexOf('nos'),
        lessThan(encliticPronouns.indexOf('os')),
      );
    });
  });
}
