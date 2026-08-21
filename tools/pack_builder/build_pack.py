"""Build a lyricanki dictionary pack from a kaikki.org extract.

Input is ``downloads/<lang>-extract.jsonl.gz`` from
``kaikki.org/dictionary/downloads/<lang>/`` -- the *current* path. The
per-language bulk file ``kaikki.org-dictionary-<Language>.jsonl`` is marked
deprecated upstream; do not switch to it.

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

from schema import create_schema, write_meta

# Wiktionary marks non-lemma entries with these tags; carding them would
# teach "vamos" as its own headword rather than as a form of "ir".
_NON_LEMMA_TAGS = frozenset({"form-of", "inflection-of"})


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
    """Yield each JSON entry from the gzipped kaikki extract at ``path``."""
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                yield json.loads(line)


def english_glosses(entry: dict) -> list[str]:
    """Return the English translations attached to ``entry``."""
    seen: list[str] = []
    for translation in entry.get("translations") or []:
        if translation.get("lang_code") != "en":
            continue
        word = (translation.get("word") or "").strip()
        if word and word not in seen:
            seen.append(word)
    return seen


def source_gloss(entry: dict) -> str:
    """Return the first source-language definition in ``entry``."""
    for sense in entry.get("senses") or []:
        # Skip senses that only say "plural of X" -- those are inflection
        # pointers, not definitions, and make a useless card back.
        if _NON_LEMMA_TAGS & set(sense.get("tags") or []):
            continue
        for gloss in sense.get("glosses") or []:
            if gloss.strip():
                return gloss.strip()
    return ""


def is_lemma_entry(entry: dict) -> bool:
    """Whether ``entry`` is a headword rather than an inflected form."""
    tags = set(entry.get("tags") or [])
    if _NON_LEMMA_TAGS & tags:
        return False
    return bool(entry.get("word")) and bool(entry.get("pos"))


def build(
    extract: Path,
    output: Path,
    language: str,
    pack_type: str = "whitespace",
) -> BuildStats:
    """Build the pack at ``output`` from ``extract``; return its stats."""
    if output.exists():
        output.unlink()
    stats = BuildStats()
    connection = sqlite3.connect(output)
    try:
        create_schema(connection)
        senses: dict[tuple[str, str], tuple[str, str]] = {}
        forms: set[tuple[str, str, str, str]] = set()

        for entry in iter_entries(extract):
            stats.entries_read += 1
            if not is_lemma_entry(entry):
                continue
            word = entry["word"]
            pos = entry["pos"]

            english = english_glosses(entry)
            src = source_gloss(entry)
            if not english and not src:
                continue

            key = (word, pos)
            existing = senses.get(key, ("", ""))
            senses[key] = (
                existing[0] or "; ".join(english[:4]),
                existing[1] or src,
            )

            # The headword is a form of itself, so a word that never inflects
            # still resolves.
            forms.add((word.lower(), word, pos, ""))
            for form in entry.get("forms") or []:
                surface = (form.get("form") or "").strip().lower()
                if not surface or " " in surface:
                    continue
                tags = ",".join(form.get("tags") or [])
                forms.add((surface, word, pos, tags))

        connection.executemany(
            "INSERT OR REPLACE INTO senses (lemma, pos, gloss_en, gloss_src) "
            "VALUES (?, ?, ?, ?)",
            [(w, p, en, src) for (w, p), (en, src) in senses.items()],
        )
        connection.executemany(
            "INSERT OR REPLACE INTO forms (form, lemma, pos, tags) VALUES (?, ?, ?, ?)",
            sorted(forms),
        )
        stats.lemmas_written = len(senses)
        stats.forms_written = len(forms)
        stats.with_english = sum(1 for en, _ in senses.values() if en)
        stats.source_gloss_only = sum(
            1 for en, src in senses.values() if not en and src
        )
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
    parser.add_argument("--extract", type=Path, required=True)
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
