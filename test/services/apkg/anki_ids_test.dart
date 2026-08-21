import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/apkg/anki_ids.dart';

void main() {
  group('base91 table', () {
    test('is exactly 91 characters with no duplicates', () {
      expect(base91Table.length, 91);
      expect(base91Table.split('').toSet().length, 91);
    });

    test('excludes quote, backslash and space', () {
      expect(base91Table.contains("'"), isFalse);
      expect(base91Table.contains('"'), isFalse);
      expect(base91Table.contains(r'\'), isFalse);
      expect(base91Table.contains(' '), isFalse);
    });
  });

  group('encodeBase91', () {
    test('returns empty for zero, matching Anki and genanki', () {
      expect(encodeBase91(BigInt.zero), '');
    });

    test('encodes single digits as the table character', () {
      expect(encodeBase91(BigInt.one), 'b');
      expect(encodeBase91(BigInt.from(90)), '~');
    });

    test('rolls over to two digits at the radix', () {
      expect(encodeBase91(BigInt.from(91)), 'ba');
    });
  });

  group('guidFor', () {
    // Golden values produced by genanki 0.13.1's own guid_for() and diffed
    // against this implementation. If these change, the deck stops updating in
    // place and starts duplicating on re-import.
    const goldens = <String, String>{
      'es|corazón': r'vId^YY^F=-',
      'es|estar': r'D$U)^^z2x6',
      'es|amor': r'c^rAi&mlk4',
      'es|despacito': r'AH:k6e&w<.',
    };

    goldens.forEach((key, expected) {
      test('matches the genanki golden for $key', () {
        expect(guidFor(key), expected);
      });
    });

    test('is stable across calls', () {
      expect(guidFor('es|amor'), guidFor('es|amor'));
    });

    test('differs by language, so one lemma can card twice', () {
      expect(guidFor('es|amor'), isNot(guidFor('fr|amor')));
    });

    test('handles accented and multi-byte input', () {
      expect(guidFor('es|ñandú').isNotEmpty, isTrue);
    });
  });

  group('csumFor', () {
    // genanki writes a literal 0 here; AnkiDroid needs the real value for
    // duplicate detection, so these goldens come from Anki's own definition:
    // int(sha1_hex(field)[:8], 16).
    const goldens = <String, int>{
      'corazón': 3703459283,
      'estar': 3341744486,
      'amor': 4117751436,
      'despacito': 1375494461,
    };

    goldens.forEach((field, expected) {
      test('matches the Anki golden for $field', () {
        expect(csumFor(field), expected);
      });
    });

    test('is never the genanki placeholder for real input', () {
      expect(csumFor('amor'), isNot(0));
    });

    test('fits an unsigned 32-bit range', () {
      for (final field in goldens.keys) {
        expect(csumFor(field), inInclusiveRange(0, 4294967295));
      }
    });
  });
}
