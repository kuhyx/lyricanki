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


def test_ingest_skips_a_form_without_a_surface(tmp_path: Path) -> None:
    extract = _write(
        tmp_path / "e.jsonl",
        [_entry(senses=[{"glosses": ["love"]}], forms=[{"form": ""}])],
    )
    build([extract], tmp_path / "p.sqlite", "es")


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


def test_build_ignores_blank_lines_in_an_extract(tmp_path: Path) -> None:
    """kaikki files end with a newline, so the reader must skip empties."""
    path = tmp_path / "e.jsonl"
    path.write_text(
        "\n" + json.dumps(_entry(senses=[{"glosses": ["love"]}])) + "\n\n",
        encoding="utf-8",
    )
    stats = build([path], tmp_path / "p.sqlite", "es")
    assert stats.entries_read == 1

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
