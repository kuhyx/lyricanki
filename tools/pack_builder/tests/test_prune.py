"""Tests for dropping pack rows that cannot become a usable card."""

from __future__ import annotations

import sqlite3

from prune import drop_nominalised_infinitives
from schema import create_schema


def _pack(rows: list[tuple[str, str, str]]) -> sqlite3.Connection:
    """Return an in-memory pack holding ``rows`` of (lemma, pos, gloss_en)."""
    connection = sqlite3.connect(":memory:")
    create_schema(connection)
    connection.executemany(
        "INSERT INTO senses (lemma, pos, gloss_en) VALUES (?, ?, ?)", rows
    )
    return connection


def _nouns(connection: sqlite3.Connection) -> list[str]:
    return [
        lemma
        for lemma, in connection.execute(
            "SELECT lemma FROM senses WHERE pos = 'noun' ORDER BY lemma"
        )
    ]


def test_drops_the_nominalised_infinitive() -> None:
    # Wiktionary lists `estar` as a noun glossed "be" alongside the verb.
    connection = _pack(
        [
            ("estar", "noun", "be"),
            ("estar", "verb", "to be (in a place); to be present"),
        ]
    )
    drop_nominalised_infinitives(connection)

    assert _nouns(connection) == []
    assert connection.execute(
        "SELECT COUNT(*) FROM senses WHERE pos = 'verb'"
    ).fetchone() == (1,)


def test_drops_when_the_verb_sense_has_no_parenthetical() -> None:
    connection = _pack(
        [("valer", "noun", "be worth"), ("valer", "verb", "to be worth")]
    )
    drop_nominalised_infinitives(connection)

    assert _nouns(connection) == []


def test_keeps_a_noun_that_means_something_else() -> None:
    # `anular` is genuinely both "to annul" and "ring finger"; a looser rule
    # keyed on "noun and verb share a lemma" would delete real vocabulary.
    connection = _pack(
        [("anular", "noun", "ring finger"), ("anular", "verb", "to annul")]
    )
    drop_nominalised_infinitives(connection)

    assert _nouns(connection) == ["anular"]


def test_keeps_a_noun_with_no_verb_of_the_same_lemma() -> None:
    connection = _pack([("amor", "noun", "love; love affair")])
    drop_nominalised_infinitives(connection)

    assert _nouns(connection) == ["amor"]


def test_keeps_a_multi_sense_noun() -> None:
    # More than one sense means the noun carries meaning of its own.
    connection = _pack(
        [
            ("comer", "noun", "eating; food"),
            ("comer", "verb", "to eating"),
        ]
    )
    drop_nominalised_infinitives(connection)

    assert _nouns(connection) == ["comer"]


def test_keeps_a_long_noun_gloss() -> None:
    # Over 30 characters is a definition, not a bare nominalisation.
    gloss = "the act of opening something up"
    connection = _pack(
        [("abrir", "noun", gloss), ("abrir", "verb", f"to {gloss}")]
    )
    drop_nominalised_infinitives(connection)

    assert _nouns(connection) == ["abrir"]


def test_keeps_a_noun_whose_gloss_is_empty() -> None:
    connection = _pack([("xx", "noun", ""), ("xx", "verb", "to xx")])
    drop_nominalised_infinitives(connection)

    assert _nouns(connection) == ["xx"]
