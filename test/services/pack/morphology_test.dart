import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/pack/morphology.dart';

void main() {
  group('diminutiveBases', () {
    test('recovers despacio from the song title', () {
      expect(diminutiveBases('despacito'), contains('despacio'));
    });

    test('recovers suave from suavecito, handling the inserted -c-', () {
      expect(diminutiveBases('suavecito'), contains('suave'));
    });

    test('yields nothing for a word with no diminutive suffix', () {
      expect(diminutiveBases('corazón'), isEmpty);
    });

    test('refuses a stem too short to be a real base', () {
      // "ito" alone leaves nothing; inventing a base from it would card noise.
      expect(diminutiveBases('ito'), isEmpty);
      expect(diminutiveBases('mito'), isEmpty);
    });

    test('recovers ojo from the plural ojitos, a 2-letter stem', () {
      expect(diminutiveBases('ojitos'), contains('ojo'));
    });

    test('never yields a bare 2-letter stem such as the pronoun os', () {
      expect(diminutiveBases('ositos'), isNot(contains('os')));
    });

    test('never yields the surface itself', () {
      expect(diminutiveBases('gatito'), isNot(contains('gatito')));
    });

    test('does not repeat a candidate reachable two ways', () {
      final bases = diminutiveBases('suavecito').toList();
      expect(bases.length, bases.toSet().length);
    });
  });

  group('elisionBases', () {
    test('restores the dropped s of a sung first person plural', () {
      expect(elisionBases('vamo'), <String>['vamos']);
    });

    test("restores the dropped d of a sung participle (esta'o)", () {
      expect(elisionBases("esta'o"), <String>['estado']);
      expect(elisionBases('cansa’a'), <String>['cansada']);
    });

    test('yields nothing for a word that does not end in -mo', () {
      expect(elisionBases('vamos'), isEmpty);
    });
  });

  group('recover', () {
    test('returns a diminutive base when the pack knows it', () {
      expect(recover('despacito', (c) => c == 'despacio'), 'despacio');
    });

    test('returns an elision base when the pack knows it', () {
      expect(recover('vamo', (c) => c == 'vamos'), 'vamos');
    });

    test('returns null when no rewrite is known, never inventing a word', () {
      expect(recover('dididiri', (_) => false), isNull);
      expect(recover('despacito', (_) => false), isNull);
    });

    test('prefers the diminutive reading, which cannot overlap an elision', () {
      // No diminutive suffix ends in "mo", so this ordering is safe.
      expect(recover('gatito', (_) => true), isNot('gatitos'));
    });
  });
}
