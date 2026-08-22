import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/gloss_fallback.dart';

/// Tests for the two pure parsing helpers.
///
/// Split from `gloss_fallback_test.dart` to hold the 250-line cap; the
/// division is by subject -- HTML parsing here, the HTTP client there.
void main() {
  group('stripHtml', () {
    test('removes tags and collapses whitespace', () {
      expect(stripHtml('<i>heart</i>  of\n the body'), 'heart of the body');
    });

    test('decodes the entities Wiktionary emits', () {
      expect(
        stripHtml('a &amp; b &quot;c&quot; &#39;d&#39;'),
        'a & b "c" \'d\'',
      );
    });

    test('returns empty for markup with no text', () {
      expect(stripHtml('<span></span>'), '');
    });
  });

  group('formOfTarget', () {
    test('extracts the lemma an inflection points at', () {
      const html =
          '<span class="form-of-definition">inflection of '
          '<a href="/wiki/estar#Spanish">estar</a></span>';
      expect(formOfTarget(html), 'estar');
    });

    test('decodes a percent-encoded lemma', () {
      const html =
          '<span class="form-of-definition">'
          '<a href="/wiki/coraz%C3%B3n#Spanish">x</a></span>';
      expect(formOfTarget(html), 'corazón');
    });

    test('returns null for an ordinary definition', () {
      expect(formOfTarget('heart (organ of the body)'), isNull);
    });

    test('returns null when the marker is present but no link is', () {
      expect(formOfTarget('<span class="form-of-definition"></span>'), isNull);
    });
  });
}
