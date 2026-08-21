import 'package:flutter_test/flutter_test.dart';
import 'package:lyricanki/services/pack/pack_reader.dart';
import 'package:lyricanki/services/pipeline/deck_builder.dart';

import '../pack/pack_reader_test.dart' show buildPack;

void main() {
  late PackReader pack;
  late DeckBuilder builder;

  setUp(() {
    pack = PackReader.fromDatabase(buildPack());
    builder = DeckBuilder(pack: pack, languageCode: 'es');
  });
  tearDown(() => pack.close());

  test('builds one card per resolvable word', () {
    final draft = builder.build('Corazón suave');
    expect(draft.cards.map((c) => c.lemma), <String>['corazón', 'suave']);
    expect(draft.unresolved, isEmpty);
  });

  test('collapses inflections of one verb onto a single card', () {
    // está and estás are two surfaces, one lemma -- this collapse is why the
    // card count sits far below the surface count.
    final draft = builder.build('Está\nEstás');
    expect(draft.cards, hasLength(1));
    expect(draft.cards.single.lemma, 'estar');
  });

  test('merges parts of speech into one card rather than losing one', () {
    // In the real pack the surface `tu` ranks to the determiner while `tus`
    // resolves to the adjective -- two surfaces, one lemma, two readings. Q19
    // keys the guid on es|<lemma>, so emitting two notes would collide on
    // import and silently drop the second reading; they merge instead.
    final draft = builder.build('Tu cuerpo\nTus ojos');
    expect(draft.cards, hasLength(1));
    final card = draft.cards.single;
    expect(card.lemma, 'tu');
    expect(card.pos, 'det/adj');
    expect(card.gloss, 'apocopic form of tuyo; your');
    // Context stays the first line the word was met in.
    expect(card.line, 'Tu cuerpo');
  });

  test('keeps the first line a word appeared in as its context', () {
    final draft = builder.build('Primera corazón\nSegunda corazón');
    expect(draft.cards.single.line, 'Primera corazón');
  });

  test('reports unresolved surfaces rather than swallowing them', () {
    final draft = builder.build('Corazón dididiri woah');
    expect(draft.cards.map((c) => c.lemma), <String>['corazón']);
    expect(draft.unresolved, <String>['dididiri', 'woah']);
  });

  test('keeps function words: inclusion is the user choice, not a filter', () {
    final draft = builder.build('Me');
    expect(draft.cards.single.lemma, 'me');
  });

  test('every card it emits is exportable', () {
    final draft = builder.build('Corazón me tu suave vamo dámelo');
    expect(draft.cards.every((c) => c.isExportable), isTrue);
    expect(draft.cards, isNotEmpty);
  });

  test('handles empty lyrics', () {
    final draft = builder.build('');
    expect(draft.cards, isEmpty);
    expect(draft.unresolved, isEmpty);
  });

  test('rejects a language with no whitespace tokenizer', () {
    expect(
      () => DeckBuilder(pack: pack, languageCode: 'zh'),
      throwsArgumentError,
    );
  });
}
