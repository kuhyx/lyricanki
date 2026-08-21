import 'package:lyricanki/models/vocab_card.dart';
import 'package:lyricanki/services/pack/enclitics.dart';
import 'package:lyricanki/services/pack/morphology.dart';
import 'package:lyricanki/services/pack/ranking.dart';
import 'package:sqlite3/sqlite3.dart';

/// One (lemma, pos) candidate from the pack.
typedef LemmaRow = ({String lemma, String pos});

/// Reads a downloaded dictionary pack and resolves surface forms to cards.
///
/// The pack is the only per-language artifact: there are no per-language code
/// paths here beyond the tokenizer the pack's `pack_type` names.
class PackReader {
  /// Opens the pack at [path] read-only.
  PackReader.open(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  /// Wraps an already-open [database], for tests and in-memory packs.
  PackReader.fromDatabase(Database database) : _db = database;

  final Database _db;

  /// Returns the pack's `meta` value for [key], or `null`.
  String? meta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Returns every (lemma, pos) candidate for the surface form [form].
  ///
  /// Deliberately many-to-one: `fue` is both *ser* and *ir*, and picking a
  /// single winner in the query would silently mis-teach the word.
  List<LemmaRow> candidates(String form) {
    final rows = _db.select(
      'SELECT lemma, pos FROM forms WHERE form = ?',
      [form],
    );
    return <LemmaRow>[
      for (final row in rows)
        (lemma: row['lemma'] as String, pos: row['pos'] as String),
    ];
  }

  /// Returns the English gloss for [lemma]/[pos], or `''` when there is none.
  String gloss(String lemma, String pos) {
    final rows = _db.select(
      'SELECT gloss_en FROM senses WHERE lemma = ? AND pos = ?',
      [lemma, pos],
    );
    return rows.isEmpty ? '' : rows.first['gloss_en'] as String;
  }

  /// Whether [lemma]/[pos] has a non-empty English gloss.
  bool hasGloss(String lemma, String pos) => gloss(lemma, pos).isNotEmpty;

  /// Resolves [surface] to its best (lemma, pos), or `null`.
  ///
  /// Three stages, in the order `tools/pack_builder` measures with: a direct
  /// `forms` hit, then enclitic splitting, then morphological recovery for
  /// diminutives and sung elisions. The two implementations must agree — if
  /// they diverge, the app's card count stops matching the fixture.
  LemmaRow? resolve(String surface) {
    final direct = candidates(surface);
    if (direct.isNotEmpty) {
      return bestCandidate(surface, direct, hasEnglish: hasGloss);
    }
    final enclitic = resolveEnclitic(surface, candidates);
    if (enclitic != null) {
      return enclitic;
    }
    final base = recover(
      surface,
      (candidate) => candidates(candidate).isNotEmpty,
    );
    if (base != null) {
      return bestCandidate(base, candidates(base), hasEnglish: hasGloss);
    }
    return null;
  }

  /// Builds a card for [surface] met in [line], or `null` if unresolvable.
  ///
  /// Returns `null` rather than a card with an empty gloss: the done condition
  /// forbids notes whose gloss is empty or equal to the word.
  VocabCard? cardFor(String surface, String line) {
    final row = resolve(surface);
    if (row == null) {
      return null;
    }
    final text = gloss(row.lemma, row.pos);
    if (text.isEmpty) {
      return null;
    }
    final card = VocabCard(
      lemma: row.lemma,
      pos: row.pos,
      gloss: text,
      line: line,
    );
    return card.isExportable ? card : null;
  }

  /// Closes the underlying database.
  void close() => _db.close();
}
