import 'package:flutter/foundation.dart';

/// The licence notices the pack and lyrics sources require.
///
/// Not decoration: the pack is built from Wiktionary data via kaikki.org under
/// CC BY-SA, which requires crediting the source and naming the licence, and
/// the lyrics come from LRCLIB. They live in Flutter's licence page rather
/// than on the pack screen, so they are one tap on the (c) glyph away instead
/// of three paragraphs painted on every visit (kuhy's textgate rule).
const List<(String, String)> attributionNotices = <(String, String)>[
  (
    'Wiktionary (kaikki.org)',
    'Dictionary data from Wiktionary via kaikki.org, used under CC BY-SA 4.0 '
        'and the GFDL. Definitions fetched online come from English '
        'Wiktionary under CC BY-SA 3.0 and the GFDL.',
  ),
  ('LRCLIB (lrclib.net)', 'Lyrics from LRCLIB (lrclib.net).'),
];

bool _registered = false;

/// Adds [attributionNotices] to the [LicenseRegistry], once per process.
void registerAttributions() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.fromIterable(<LicenseEntry>[
      for (final (source, notice) in attributionNotices)
        LicenseEntryWithLineBreaks(<String>[source], notice),
    ]),
  );
}
