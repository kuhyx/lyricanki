"""Drop everything from a built pack that cannot become a card."""

from __future__ import annotations

import sqlite3


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


