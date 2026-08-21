/// Builds the JSON blobs stored in `col.models`, `col.decks`, `col.conf` and
/// `col.dconf`.
///
/// Anki keeps these as JSON text inside the collection row rather than as
/// tables, so they are constructed here and encoded once.
library;

import 'dart:convert';

import 'package:lyricanki/services/apkg/collection_schema.dart';

/// Returns the `col.models` JSON: a single note type keyed by [modelId].
///
/// The templates are plain text with no styling beyond the shared `css`, and
/// the card asks word -> gloss. `sortf: 0` sorts by `Word`, which matches
/// `notes.sfld` being the first field.
String buildModelsJson({required String deckName}) {
  final fields = <Map<String, Object?>>[
    for (var i = 0; i < fieldNames.length; i++)
      <String, Object?>{
        'name': fieldNames[i],
        'ord': i,
        'sticky': false,
        'rtl': false,
        'font': 'Arial',
        'size': 20,
        'media': <String>[],
      },
  ];

  final model = <String, Object?>{
    'id': modelId,
    'name': 'lyricanki $deckName',
    'type': 0,
    'mod': 0,
    'usn': -1,
    'sortf': 0,
    'did': deckId,
    'tmpls': <Map<String, Object?>>[
      <String, Object?>{
        'name': 'Word -> Gloss',
        'ord': 0,
        // The lyric line is the context that makes the word memorable, so it
        // is on the back with the gloss, not the front: showing it on the
        // front would give the answer away by association.
        'qfmt': '{{Word}}',
        'afmt':
            '{{FrontSide}}\n\n<hr id=answer>\n\n'
            '{{Gloss}}\n\n<div class=pos>{{POS}}</div>\n'
            '<div class=line>{{Line}}</div>',
        'bqfmt': '',
        'bafmt': '',
        'did': null,
        'bfont': '',
        'bsize': 0,
      },
    ],
    'flds': fields,
    'css':
        '.card { font-family: arial; font-size: 20px; text-align: center; '
        'color: black; background-color: white; }\n'
        '.pos { font-size: 14px; color: #666; }\n'
        '.line { font-size: 16px; color: #444; font-style: italic; '
        'margin-top: 8px; }',
    'latexPre': '',
    'latexPost': '',
    'latexsvg': false,
    'req': <List<Object?>>[
      <Object?>[
        0,
        'any',
        <int>[0],
      ],
    ],
    'tags': <String>[],
    'vers': <String>[],
  };

  return jsonEncode(<String, Object?>{'$modelId': model});
}

/// Returns the `col.decks` JSON.
///
/// Carries **both** the target deck and Anki's default deck `"1"`. A
/// collection missing deck 1 is rejected by some importers, and the default
/// deck is where any card with an unknown deck id would land.
String buildDecksJson({required String deckName}) {
  Map<String, Object?> deck(int id, String name) => <String, Object?>{
    'id': id,
    'name': name,
    'mod': 0,
    'usn': -1,
    'lrnToday': <int>[0, 0],
    'revToday': <int>[0, 0],
    'newToday': <int>[0, 0],
    'timeToday': <int>[0, 0],
    'collapsed': false,
    'browserCollapsed': false,
    'desc': '',
    'dyn': 0,
    'conf': 1,
    'extendNew': 10,
    'extendRev': 50,
  };

  return jsonEncode(<String, Object?>{
    '$defaultDeckId': deck(defaultDeckId, 'Default'),
    '$deckId': deck(deckId, deckName),
  });
}

/// Returns the `col.conf` JSON: collection-wide preferences.
String buildConfJson() => jsonEncode(<String, Object?>{
  'activeDecks': <int>[defaultDeckId],
  'addToCur': true,
  'collapseTime': 1200,
  'curDeck': defaultDeckId,
  'curModel': '$modelId',
  'dueCounts': true,
  'estTimes': true,
  'newBury': true,
  'newSpread': 0,
  'nextPos': 1,
  'sortBackwards': false,
  'sortType': 'noteFld',
  'timeLim': 0,
});

/// Returns the `col.dconf` JSON: the default deck options group.
String buildDconfJson() => jsonEncode(<String, Object?>{
  '1': <String, Object?>{
    'id': 1,
    'name': 'Default',
    'mod': 0,
    'usn': -1,
    'maxTaken': 60,
    'autoplay': true,
    'timer': 0,
    'replayq': true,
    'new': <String, Object?>{
      'bury': false,
      'delays': <double>[1, 10],
      'initialFactor': 2500,
      'ints': <int>[1, 4, 7],
      'order': 1,
      'perDay': 20,
    },
    'rev': <String, Object?>{
      'bury': false,
      'ease4': 1.3,
      'ivlFct': 1,
      'maxIvl': 36500,
      'perDay': 200,
      'hardFactor': 1.2,
    },
    'lapse': <String, Object?>{
      'delays': <double>[10],
      'leechAction': 1,
      'leechFails': 8,
      'minInt': 1,
      'mult': 0,
    },
    'dyn': false,
  },
});
