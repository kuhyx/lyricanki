import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:sqlite3/sqlite3.dart';

/// Builds an in-memory pack with the real schema and a handful of rows.
///
/// The fixtures mirror shapes measured in the built Spanish pack: `me` files
/// under both an initialism and a pronoun, `tu` under two parts of speech, and
/// `suave`/`vamos` exist so morphological recovery has somewhere to land.
Database buildPack() {
  final db = sqlite3.openInMemory()
    ..execute('''
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE forms (form TEXT, lemma TEXT, pos TEXT, PRIMARY KEY (form, lemma, pos));
CREATE TABLE senses (lemma TEXT, pos TEXT, gloss_en TEXT DEFAULT '', PRIMARY KEY (lemma, pos));
''');
  const forms = <List<String>>[
    <String>['corazón', 'corazón', 'noun'],
    <String>['está', 'estar', 'verb'],
    <String>['estás', 'estar', 'verb'],
    <String>['me', 'ME', 'noun'],
    <String>['me', 'me', 'pron'],
    <String>['tu', 'tu', 'det'],
    <String>['tu', 'tu', 'adj'],
    <String>['tus', 'tu', 'adj'],
    <String>['suave', 'suave', 'adj'],
    <String>['vamos', 'ir', 'verb'],
    <String>['da', 'dar', 'verb'],
    <String>['las', 'lesen', 'verb'],
    <String>['las', 'la', 'article'],
  ];
  for (final f in forms) {
    db.execute('INSERT INTO forms VALUES (?, ?, ?)', f);
  }
  const senses = <List<String>>[
    <String>['corazón', 'noun', 'heart'],
    <String>['estar', 'verb', 'to be'],
    <String>['ME', 'noun', ''],
    <String>['me', 'pron', 'me'],
    <String>['tu', 'det', 'apocopic form of tuyo'],
    <String>['tu', 'adj', 'your'],
    <String>['suave', 'adj', 'smooth, soft'],
    <String>['ir', 'verb', 'to go'],
    <String>['dar', 'verb', 'to give'],
    <String>['lesen', 'verb', ''],
    <String>['la', 'article', 'the'],
  ];
  for (final s in senses) {
    db.execute('INSERT INTO senses VALUES (?, ?, ?)', s);
  }
  db.execute("INSERT INTO meta VALUES ('pack_type', 'latin')");
  return db;
}

void main() {
  late PackReader pack;

  setUp(() => pack = PackReader.fromDatabase(buildPack()));
  tearDown(() => pack.close());

  group('meta', () {
    test('reads a known key', () {
      expect(pack.meta('pack_type'), 'latin');
    });

    test('returns null for an absent key', () {
      expect(pack.meta('nope'), isNull);
    });
  });

  group('candidates', () {
    test('returns every reading, not a single winner', () {
      expect(pack.candidates('me'), hasLength(2));
    });

    test('returns empty for an unknown form', () {
      expect(pack.candidates('dididiri'), isEmpty);
    });
  });

  group('gloss', () {
    test('returns the English gloss', () {
      expect(pack.gloss('corazón', 'noun'), 'heart');
    });

    test('returns empty for an unknown lemma', () {
      expect(pack.gloss('nope', 'noun'), '');
      expect(pack.hasGloss('nope', 'noun'), isFalse);
    });

    test('reports an empty gloss as absent', () {
      expect(pack.hasGloss('ME', 'noun'), isFalse);
      expect(pack.hasGloss('corazón', 'noun'), isTrue);
    });
  });

  group('resolve', () {
    test('resolves a direct hit', () {
      expect(pack.resolve('corazón'), (lemma: 'corazón', pos: 'noun'));
    });

    test('collapses inflections onto the lemma', () {
      expect(pack.resolve('está'), (lemma: 'estar', pos: 'verb'));
      expect(pack.resolve('estás'), (lemma: 'estar', pos: 'verb'));
    });

    test('prefers the glossed reading over an unglossed homograph', () {
      expect(pack.resolve('las'), (lemma: 'la', pos: 'article'));
      expect(pack.resolve('me'), (lemma: 'me', pos: 'pron'));
    });

    test('splits an enclitic cluster to the verb', () {
      expect(pack.resolve('dámelo'), (lemma: 'dar', pos: 'verb'));
    });

    test('recovers a diminutive', () {
      expect(pack.resolve('suavecito'), (lemma: 'suave', pos: 'adj'));
    });

    test('recovers a sung elision', () {
      expect(pack.resolve('vamo'), (lemma: 'ir', pos: 'verb'));
    });

    test('returns null for a word the pack does not have', () {
      expect(pack.resolve('dididiri'), isNull);
    });
  });

  group('open', () {
    test('opens a pack from a file path read-only', () {
      // The app opens packs by path, so the constructor the app actually uses
      // is exercised here rather than only the injectable one.
      final dir = Directory.systemTemp.createTempSync('lyricanki_pack');
      try {
        final path = '${dir.path}/pack.sqlite';
        final seed = sqlite3.open(path);
        buildPack().execute('VACUUM INTO ?', <String>[path]);
        seed.dispose();
        final onDisk = PackReader.open(path);
        expect(onDisk.meta('pack_type'), 'latin');
        expect(onDisk.resolve('corazón'), (lemma: 'corazón', pos: 'noun'));
        onDisk.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('cardFor', () {
    test('builds a card with gloss and context line', () {
      final card = pack.cardFor('corazón', 'Despacito');
      expect(card!.lemma, 'corazón');
      expect(card.pos, 'noun');
      expect(card.gloss, 'heart');
      expect(card.line, 'Despacito');
    });

    test('keeps a homograph whose gloss matches the word', () {
      expect(pack.cardFor('me', 'x')!.gloss, 'me');
    });

    test('returns null for an unresolvable surface', () {
      expect(pack.cardFor('dididiri', 'x'), isNull);
    });

    test('returns null when the resolved lemma has no gloss', () {
      // Only reading of this form is an unglossed import.
      expect(pack.cardFor('lesen', 'x'), isNull);
    });
  });
}
