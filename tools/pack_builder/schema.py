"""SQLite schema for a lyricanki dictionary pack.

A pack is the *only* per-language artifact: the app has no per-language code
paths, it reads ``meta.pack_type`` and follows the tokenizer that names.

``forms`` is deliberately one-to-many. A surface form can lemmatise several
ways -- Spanish ``fue`` is both *ser* and *ir*, ``vino`` is both "wine" and
"he came" -- and a single-lemma column silently picks a winner, which
mis-teaches the word.
"""

from __future__ import annotations

import sqlite3

SCHEMA = """
CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- surface form -> candidate lemmas. One row per (form, lemma, pos).
-- No `tags` column: the inflection labels ("first-person,singular,present")
-- cost 64MB of a 150MB pack and nothing in the pipeline reads them. The card
-- shows the lemma's part of speech, not the form's morphology.
CREATE TABLE forms (
    form  TEXT NOT NULL,
    lemma TEXT NOT NULL,
    pos   TEXT NOT NULL,
    PRIMARY KEY (form, lemma, pos)
) WITHOUT ROWID;

-- lemma -> gloss. `gloss_en` is the card back; `gloss_src` is the
-- source-language definition kept so a missing translation can be machine
-- translated later without re-reading the 95MB extract.
CREATE TABLE senses (
    lemma      TEXT NOT NULL,
    pos        TEXT NOT NULL,
    gloss_en   TEXT NOT NULL DEFAULT '',
    gloss_src  TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (lemma, pos)
) WITHOUT ROWID;

-- No index on forms(form) or senses(lemma): both tables are WITHOUT ROWID
-- with those columns leading the primary key, so the table IS the index. A
-- separate one duplicated 37MB of a 82MB pack for no lookup benefit.
"""


def create_schema(connection: sqlite3.Connection) -> None:
    """Create the pack tables on ``connection``."""
    connection.executescript(SCHEMA)


def write_meta(connection: sqlite3.Connection, values: dict[str, str]) -> None:
    """Insert or replace the ``meta`` rows from ``values``."""
    connection.executemany(
        "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
        sorted(values.items()),
    )
