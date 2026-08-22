"""Drop everything from a built pack that cannot become a card."""

from __future__ import annotations

import sqlite3


def drop_nominalised_infinitives(connection: sqlite3.Connection) -> None:
    """Drop noun senses that merely restate the verb of the same lemma.

    Wiktionary lists the nominalised infinitive as its own noun headword, so
    ``estar`` arrives as both a verb and a noun glossed "be". The noun is not
    a word anyone learns separately and it splits one lemma across two cards.

    The rule is deliberately narrow -- the noun's whole gloss must equal the
    verb's first sense with "to " removed. A looser "noun and verb share a
    lemma" rule would delete real vocabulary: ``anular`` is also "ring
    finger", ``alisar`` an "alder tree plantation", ``comer`` "eating, food".
    Measured on the Spanish pack this drops exactly two rows, ``estar`` and
    ``valer``; ``fue`` = *ser*/*ir* and every other genuine homograph is
    untouched.
    """
    doomed = []
    verbs = {
        lemma: gloss
        for lemma, gloss in connection.execute(
            "SELECT lemma, gloss_en FROM senses WHERE pos = 'verb'"
        )
    }
    for lemma, gloss in connection.execute(
        "SELECT lemma, gloss_en FROM senses WHERE pos = 'noun'"
    ):
        verb_gloss = verbs.get(lemma)
        if not verb_gloss or ";" in gloss:
            continue
        noun = gloss.strip().lower()
        first = verb_gloss.split(";")[0].strip().lower()
        if not noun or len(noun) > 30:
            continue
        if first == f"to {noun}" or first.startswith(f"to {noun} ("):
            doomed.append(lemma)
    connection.executemany(
        "DELETE FROM senses WHERE lemma = ? AND pos = 'noun'",
        [(lemma,) for lemma in doomed],
    )


def prune(connection: sqlite3.Connection) -> None:
    """Drop everything that cannot become a card.

    A lemma with no English gloss has no card back, so neither it nor its
    inflected forms can ever be used -- and forms are by far the largest
    table. ``gloss_src`` is dropped once English exists: it was only ever a
    machine-translation input, and that route was rejected for producing
    wrong glosses.

    This is deliberately *not* a top-N frequency cut. Q20 asks that no real
    word be missing, and frequency ranking cannot tell a rare real word from
    an unusable entry, whereas "has an English gloss" can.
    """
    drop_nominalised_infinitives(connection)
    connection.execute("DELETE FROM senses WHERE gloss_en = ''")
    connection.execute(
        "DELETE FROM forms WHERE NOT EXISTS ("
        "  SELECT 1 FROM senses"
        "  WHERE senses.lemma = forms.lemma AND senses.pos = forms.pos)"
    )
    # Multi-word forms never match a single token from the tokenizer.
    connection.execute("DELETE FROM forms WHERE form LIKE '% %'")
    connection.execute("UPDATE senses SET gloss_src = ''")
    # VACUUM cannot run inside a transaction, and the DELETEs above opened
    # one implicitly. Commit first, then reclaim the freed pages -- without
    # this the file keeps its pre-prune size on disk.
    connection.commit()
    connection.execute("VACUUM")
