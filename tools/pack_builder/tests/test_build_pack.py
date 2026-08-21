"""Tests for pack assembly, gloss selection and pruning."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from build_pack import build
from glosses import direct_glosses, english_glosses, is_lemma_entry, source_gloss
from prune import prune
from schema import create_schema


def _entry(**kwargs: object) -> dict:
    base = {"word": "amor", "pos": "noun", "lang_code": "es", "senses": []}
    base.update(kwargs)
    return base


def test_direct_glosses_keeps_a_real_definition() -> None:
    entry = _entry(senses=[{"glosses": ["love; love affair"]}])
    assert direct_glosses(entry) == ["love; love affair"]


def test_direct_glosses_drops_a_pure_inflection_pointer() -> None:
    """"plural of pie" defines nothing; it points at another headword."""
    entry = _entry(senses=[{"glosses": ["plural of pie"]}])
    assert direct_glosses(entry) == []


def test_direct_glosses_keeps_a_pointer_that_also_defines() -> None:
    """`me` is glossed "accusative of yo: me" -- that IS the definition."""
    entry = _entry(senses=[{"glosses": ["accusative of yo: me"]}])
    assert direct_glosses(entry) == ["accusative of yo: me"]


def test_direct_glosses_skips_form_of_senses() -> None:
    entry = _entry(senses=[{"glosses": ["x"], "tags": ["form-of"]}])
    assert direct_glosses(entry) == []


def test_english_glosses_reads_the_translation_list() -> None:
    entry = _entry(
        translations=[
            {"lang_code": "en", "word": "love"},
            {"lang_code": "fr", "word": "amour"},
            {"lang_code": "en", "word": "love"},
        ]
    )
    assert english_glosses(entry) == ["love"]


def test_source_gloss_returns_the_first_definition() -> None:
    entry = _entry(senses=[{"glosses": ["Sentimiento intenso."]}])
    assert source_gloss(entry) == "Sentimiento intenso."


def test_source_gloss_is_empty_without_senses() -> None:
    assert source_gloss(_entry()) == ""


def test_is_lemma_entry_rejects_an_inflected_form() -> None:
    assert not is_lemma_entry(_entry(tags=["form-of"]))
    assert not is_lemma_entry({"word": "x"})
    assert is_lemma_entry(_entry())


def _write(path: Path, entries: list[dict]) -> Path:
    path.write_text(
        "\n".join(json.dumps(e) for e in entries), encoding="utf-8"
    )
    return path


def test_build_writes_a_usable_pack(tmp_path: Path) -> None:
    extract = _write(
        tmp_path / "en.jsonl",
        [
            _entry(senses=[{"glosses": ["love"]}],
                   forms=[{"form": "amores"}]),
            _entry(word="ir", pos="verb", senses=[{"glosses": ["to go"]}],
                   forms=[{"form": "vamos"}, {"form": "haber ido"}]),
        ],
    )
    output = tmp_path / "pack.sqlite"
    stats = build([extract], output, "es")

    assert stats.lemmas_written == 2
    connection = sqlite3.connect(output)
    rows = connection.execute(
        "SELECT lemma, pos FROM forms WHERE form = 'vamos'"
    ).fetchall()
    assert rows == [("ir", "verb")]
    gloss = connection.execute(
        "SELECT gloss_en FROM senses WHERE lemma = 'ir'"
    ).fetchone()
    assert gloss == ("to go",)
    # Multi-word forms can never match a single token.
    assert connection.execute(
        "SELECT COUNT(*) FROM forms WHERE form = 'haber ido'"
    ).fetchone() == (0,)
    assert connection.execute(
        "SELECT value FROM meta WHERE key = 'lang'"
    ).fetchone() == ("es",)


def test_build_accepts_a_single_path(tmp_path: Path) -> None:
    extract = _write(
        tmp_path / "en.jsonl", [_entry(senses=[{"glosses": ["love"]}])]
    )
    stats = build(extract, tmp_path / "p.sqlite", "es")
    assert stats.lemmas_written == 1


def test_only_the_first_source_may_define_in_english(tmp_path: Path) -> None:
    """The Spanish extract's senses are Spanish; they must not become cards.

    Treating them as English produced a card reading "Corazón." for *corazón*.
    """
    first = _write(tmp_path / "a.jsonl", [_entry(word="sol", pos="noun")])
    second = _write(
        tmp_path / "b.jsonl",
        [_entry(word="sol", pos="noun", senses=[{"glosses": ["Estrella."]}])],
    )
    output = tmp_path / "pack.sqlite"
    build([first, second], output, "es")
    connection = sqlite3.connect(output)
    # No English anywhere, so pruning removes it rather than carding Spanish.
    assert connection.execute("SELECT COUNT(*) FROM senses").fetchone() == (0,)


def test_prune_drops_lemmas_without_english_and_their_forms() -> None:
    connection = sqlite3.connect(":memory:")
    create_schema(connection)
    connection.execute(
        "INSERT INTO senses VALUES ('ir', 'verb', 'to go', 'Andar.')"
    )
    connection.execute("INSERT INTO senses VALUES ('xx', 'verb', '', 'Nada.')")
    connection.executemany(
        "INSERT INTO forms VALUES (?, ?, ?)",
        [("vamos", "ir", "verb"), ("xxs", "xx", "verb")],
    )
    prune(connection)

    assert connection.execute("SELECT COUNT(*) FROM senses").fetchone() == (1,)
    assert connection.execute("SELECT COUNT(*) FROM forms").fetchone() == (1,)
    # gloss_src was only ever an MT input, and MT was rejected.
    assert connection.execute(
        "SELECT gloss_src FROM senses"
    ).fetchone() == ("",)


def test_build_replaces_an_existing_pack(tmp_path: Path) -> None:
    output = tmp_path / "pack.sqlite"
    output.write_bytes(b"stale")
    extract = _write(
        tmp_path / "en.jsonl", [_entry(senses=[{"glosses": ["love"]}])]
    )
    build([extract], output, "es")
    assert sqlite3.connect(output).execute(
        "SELECT COUNT(*) FROM senses"
    ).fetchone() == (1,)


@pytest.mark.parametrize("suffix", [".jsonl", ".jsonl.gz"])
def test_build_reads_both_plain_and_gzipped(tmp_path: Path, suffix: str) -> None:
    import gzip

    entries = [_entry(senses=[{"glosses": ["love"]}])]
    path = tmp_path / f"e{suffix}"
    payload = json.dumps(entries[0]) + "\n"
    if suffix.endswith(".gz"):
        path.write_bytes(gzip.compress(payload.encode()))
    else:
        path.write_text(payload, encoding="utf-8")
    stats = build([path], tmp_path / f"p{suffix}.sqlite", "es")
    assert stats.lemmas_written == 1


def test_source_gloss_skips_an_inflection_sense() -> None:
    """A `form-of` sense is a pointer, so it must not become the definition."""
    entry = _entry(
        senses=[
            {"glosses": ["plural of amor"], "tags": ["form-of"]},
            {"glosses": ["Sentimiento."]},
        ]
    )
    assert source_gloss(entry) == "Sentimiento."


def test_ingest_skips_a_non_lemma_entry(tmp_path: Path) -> None:
    extract = _write(
        tmp_path / "e.jsonl",
        [
            _entry(tags=["form-of"], senses=[{"glosses": ["plural"]}]),
            _entry(word="sol", senses=[{"glosses": ["sun"]}]),
        ],
    )
    stats = build([extract], tmp_path / "p.sqlite", "es")
    assert stats.entries_read == 2
    assert stats.lemmas_written == 1


def test_main_builds_from_the_command_line(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    import build_pack

    extract = _write(
        tmp_path / "e.jsonl", [_entry(senses=[{"glosses": ["love"]}])]
    )
    output = tmp_path / "pack.sqlite"
    monkeypatch.setattr(
        "sys.argv",
        [
            "build_pack.py",
            "--extract", str(extract),
            "--output", str(output),
            "--language", "es",
        ],
    )
    build_pack.main()
    out = capsys.readouterr().out
    assert "lemmas       : 1" in out
    assert output.exists()


def test_direct_glosses_exhausts_senses_without_a_usable_gloss() -> None:
    entry = _entry(senses=[{"glosses": ["plural of x"]}, {"glosses": [""]}])
    assert direct_glosses(entry) == []


def test_english_glosses_skips_entries_without_a_word() -> None:
    entry = _entry(translations=[{"lang_code": "en", "word": ""}])
    assert english_glosses(entry) == []


def test_ingest_skips_a_form_without_a_surface(tmp_path: Path) -> None:
    extract = _write(
        tmp_path / "e.jsonl",
        [_entry(senses=[{"glosses": ["love"]}], forms=[{"form": ""}])],
    )
    build([extract], tmp_path / "p.sqlite", "es")


def test_direct_glosses_scans_every_gloss_of_a_sense() -> None:
    """A sense can hold several glosses; all are collected in order."""
    entry = _entry(senses=[{"glosses": ["love", "affection"]}])
    assert direct_glosses(entry) == ["love", "affection"]


def test_direct_glosses_skips_a_blank_gloss_and_continues() -> None:
    entry = _entry(senses=[{"glosses": ["", "love"]}])
    assert direct_glosses(entry) == ["love"]


def test_direct_glosses_deduplicates_repeated_text() -> None:
    entry = _entry(senses=[{"glosses": ["love"]}, {"glosses": ["love"]}])
    assert direct_glosses(entry) == ["love"]


def test_ingest_keeps_scanning_forms_after_a_multiword_one(
    tmp_path: Path,
) -> None:
    extract = _write(
        tmp_path / "e.jsonl",
        [
            _entry(
                word="ir", pos="verb", senses=[{"glosses": ["to go"]}],
                forms=[{"form": "haber ido"}, {"form": "vamos"}],
            )
        ],
    )
    output = tmp_path / "p.sqlite"
    build([extract], output, "es")
    assert sqlite3.connect(output).execute(
        "SELECT COUNT(*) FROM forms WHERE form = 'vamos'"
    ).fetchone() == (1,)


def test_source_gloss_exhausts_all_senses_without_a_definition() -> None:
    """Every sense is a pointer or blank, so the loop runs to completion."""
    entry = _entry(
        senses=[
            {"glosses": ["plural of x"], "tags": ["form-of"]},
            {"glosses": [""]},
            {},
        ]
    )
    assert source_gloss(entry) == ""


def test_build_ignores_blank_lines_in_an_extract(tmp_path: Path) -> None:
    """kaikki files end with a newline, so the reader must skip empties."""
    path = tmp_path / "e.jsonl"
    path.write_text(
        "\n" + json.dumps(_entry(senses=[{"glosses": ["love"]}])) + "\n\n",
        encoding="utf-8",
    )
    stats = build([path], tmp_path / "p.sqlite", "es")
    assert stats.entries_read == 1
