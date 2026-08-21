import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/pack/ranking.dart';

typedef Row = ({String lemma, String pos});

Row row(String lemma, String pos) => (lemma: lemma, pos: pos);

void main() {
  group('posScore', () {
    test('ranks function words above nouns', () {
      expect(posScore('verb'), lessThan(posScore('noun')));
      expect(posScore('pron'), lessThan(posScore('noun')));
    });

    test('penalises the categories a singer never means', () {
      for (final pos in posPenalty) {
        expect(posScore(pos), greaterThan(posScore('noun')));
      }
    });

    test('places an unknown pos below the ranked ones but above penalised', () {
      expect(posScore('particle'), greaterThan(posScore('num')));
      expect(posScore('particle'), lessThan(posScore('name')));
    });
  });

  group('bestCandidate', () {
    test('returns null for no candidates', () {
      expect(bestCandidate('x', <Row>[]), isNull);
    });

    test('prefers the lowercase lemma over a proper noun', () {
      // The lyric said amor, not the surname Amor.
      final best = bestCandidate('amor', <Row>[
        row('Amor', 'name'),
        row('amor', 'noun'),
      ]);
      expect(best, row('amor', 'noun'));
    });

    test('rejects the initialism reading of me', () {
      // ME is "muerte encefálica" -- brain death. Not what the singer meant.
      final best = bestCandidate('me', <Row>[
        row('ME', 'noun'),
        row('me', 'pron'),
      ]);
      expect(best, row('me', 'pron'));
    });

    test('does not card a single letter as a character entry', () {
      final best = bestCandidate('d', <Row>[
        row('D', 'character'),
        row('d', 'prep'),
      ]);
      expect(best, row('d', 'prep'));
    });

    test('pins a function word to the sense a lyric uses', () {
      // `no` also files as an abbreviation of noroeste and as a noun.
      final best = bestCandidate('no', <Row>[
        row('NO', 'noun'),
        row('no', 'noun'),
        row('no', 'intj'),
        row('no', 'adv'),
      ]);
      expect(best, row('no', 'adv'));
    });

    test('pins y to the conjunction, not a rarer pronoun reading', () {
      final best = bestCandidate('y', <Row>[
        row('y', 'pron'),
        row('y', 'conj'),
      ]);
      expect(best, row('y', 'conj'));
    });

    test('prefers a candidate that actually carries an English gloss', () {
      // `las` is also German lesen; that entry has no English gloss and would
      // produce a card with no usable back.
      final best = bestCandidate(
        'las',
        <Row>[row('lesen', 'verb'), row('la', 'article')],
        hasEnglish: (lemma, pos) => lemma == 'la',
      );
      expect(best, row('la', 'article'));
    });

    test('gloss beats the pos ranking, since an unglossed card is useless', () {
      final best = bestCandidate(
        'x',
        <Row>[row('averb', 'verb'), row('anoun', 'noun')],
        hasEnglish: (lemma, pos) => lemma == 'anoun',
      );
      expect(best, row('anoun', 'noun'));
    });

    test('breaks a full tie on the lemma, so ordering is deterministic', () {
      final first = bestCandidate('x', <Row>[
        row('beta', 'noun'),
        row('alpha', 'noun'),
      ]);
      final second = bestCandidate('x', <Row>[
        row('alpha', 'noun'),
        row('beta', 'noun'),
      ]);
      expect(first, row('alpha', 'noun'));
      expect(first, second);
    });

    test('keeps an uppercase lemma when the surface is uppercase too', () {
      final best = bestCandidate('OK', <Row>[row('OK', 'intj')]);
      expect(best, row('OK', 'intj'));
    });
  });

  group('rankCandidates', () {
    test('returns every candidate, best first', () {
      final ranked = rankCandidates('me', <Row>[
        row('ME', 'noun'),
        row('me', 'pron'),
      ]);
      expect(ranked, hasLength(2));
      expect(ranked.first, row('me', 'pron'));
    });

    test('does not mutate the input list', () {
      final input = <Row>[row('ME', 'noun'), row('me', 'pron')];
      rankCandidates('me', input);
      expect(input.first, row('ME', 'noun'));
    });
  });
}
