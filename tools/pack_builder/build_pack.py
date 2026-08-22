"""Build a lyricanki dictionary pack from a kaikki.org extract.

Two sources, merged by ``--extract`` being passed more than once:

* ``kaikki.org-dictionary-Spanish.jsonl`` -- English Wiktionary's view of
  Spanish words. Its sense glosses are already English ("gratis" -> "free,
  without charge"), which is what a card back needs. Marked DEPRECATED
  upstream, so snapshot it and record the date; if it disappears, fall back
  to the current path plus machine translation, accepting worse glosses.
* ``downloads/es/es-extract.jsonl.gz`` -- the current per-language path,
  richer in inflected ``forms``.

Never shipped: this is a developer tool that produces the SQLite pack the app
downloads.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sqlite3
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path

from glosses import (
    direct_glosses,
    english_glosses,
    is_lemma_entry,
    source_gloss,
    trim_long_senses,
)
from prune import prune
from schema import create_schema, write_meta

@dataclass
class BuildStats:
    """Counters describing one build, reported for the invariant check."""

    entries_read: int = 0
    lemmas_written: int = 0
    forms_written: int = 0
    with_english: int = 0
    source_gloss_only: int = 0
    missing: list[str] = field(default_factory=list)


def iter_entries(path: Path) -> Iterator[dict]:
    """Yield each JSON entry from a kaikki extract, gzipped or plain."""
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                yield json.loads(line)


def _ingest(
    source: Path,
    senses: dict[tuple[str, str], tuple[str, str]],
    forms: set[tuple[str, str, str]],
    stats: BuildStats,
    *,
    defines_in_english: bool,
) -> None:
    """Merge one extract into ``senses`` and ``forms``.

    ``defines_in_english`` marks a source whose sense glosses are written in
    English (English Wiktionary's view of Spanish). Only such a source may
    supply ``gloss_en``: the Spanish extract's senses are Spanish definitions,
    and treating them as English produced cards reading "Corazón." for
    *corazón*.
    """
    for entry in iter_entries(source):
        stats.entries_read += 1
        if not is_lemma_entry(entry):
            continue
        word = entry["word"]
        pos = entry["pos"]

        # Prefer a definition stated in English (English Wiktionary), then an
        # English translation list (Spanish Wiktionary), then the
        # source-language definition as a last resort.
        direct = direct_glosses(entry) if defines_in_english else []
        english = direct or english_glosses(entry)
        src = "" if direct else source_gloss(entry)
        if not english and not src:
            continue

        key = (word, pos)
        existing_en, existing_src = senses.get(key, ("", ""))
        candidate_en = trim_long_senses("; ".join(english[:4]))
        # A gloss written IN English beats one merely carried alongside a
        # Spanish definition: both sources define e.g. `me` as a pronoun, but
        # only English Wiktionary's is readable on a card back.
        if direct and candidate_en:
            chosen_en = candidate_en
        else:
            chosen_en = existing_en or candidate_en
        senses[key] = (chosen_en, existing_src or src)

        # The headword is a form of itself, so a word that never inflects
        # still resolves.
        forms.add((word.lower(), word, pos))
        for form in entry.get("forms") or []:
            surface = (form.get("form") or "").strip().lower()
            if not surface or " " in surface:
                continue
            forms.add((surface, word, pos))


def build(
    extracts: Path | list[Path],
    output: Path,
    language: str,
    pack_type: str = "whitespace",
) -> BuildStats:
    """Build the pack at ``output`` from one or more ``extracts``.

    Sources are merged in order and the first non-empty value wins, so pass
    the English-definition source first and the form-rich source second.
    """
    sources = [extracts] if isinstance(extracts, Path) else list(extracts)
    if output.exists():
        output.unlink()
    stats = BuildStats()
    connection = sqlite3.connect(output)
    try:
        create_schema(connection)
        senses: dict[tuple[str, str], tuple[str, str]] = {}
        forms: set[tuple[str, str, str]] = set()

        for index, source in enumerate(sources):
            # The first source is the English-definition one by contract
            # (see the module docstring); later sources only fill gaps and
            # contribute inflected forms.
            _ingest(
                source,
                senses,
                forms,
                stats,
                defines_in_english=index == 0,
            )

        connection.executemany(
            "INSERT OR REPLACE INTO senses (lemma, pos, gloss_en, gloss_src) "
            "VALUES (?, ?, ?, ?)",
            [(w, p, en, src) for (w, p), (en, src) in senses.items()],
        )
        connection.executemany(
            "INSERT OR REPLACE INTO forms (form, lemma, pos) VALUES (?, ?, ?)",
            sorted(forms),
        )
        stats.with_english = sum(1 for en, _ in senses.values() if en)
        stats.source_gloss_only = sum(
            1 for en, src in senses.values() if not en and src
        )
        prune(connection)
        stats.lemmas_written = connection.execute(
            "SELECT COUNT(*) FROM senses"
        ).fetchone()[0]
        stats.forms_written = connection.execute(
            "SELECT COUNT(*) FROM forms"
        ).fetchone()[0]
        write_meta(
            connection,
            {
                "lang": language,
                "pack_type": pack_type,
                "tokenizer": pack_type,
                "lemma_count": str(stats.lemmas_written),
                "form_count": str(stats.forms_written),
                "source": "kaikki.org wiktextract",
                "licence": "CC BY-SA (Wiktionary)",
            },
        )
        connection.commit()
    finally:
        connection.close()
    return stats


def main() -> None:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--extract", type=Path, required=True, action="append",
        help="kaikki extract; repeat, English-definition source first",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--language", required=True)
    parser.add_argument("--pack-type", default="whitespace")
    args = parser.parse_args()

    stats = build(args.extract, args.output, args.language, args.pack_type)
    print(f"entries read : {stats.entries_read}")
    print(f"lemmas       : {stats.lemmas_written}")
    print(f"forms        : {stats.forms_written}")
    print(f"with English : {stats.with_english}")
    print(f"source only  : {stats.source_gloss_only}")
    print(
        f"pack         : {args.output} "
        f"({args.output.stat().st_size / 1_048_576:.1f} MB)"
    )


if __name__ == "__main__":
    main()
