"""Extract card-ready glosses from a kaikki entry."""

from __future__ import annotations

# Wiktionary marks non-lemma entries with these tags; carding them would
# teach "vamos" as its own headword rather than as a form of "ir".
NON_LEMMA_TAGS = frozenset({"form-of", "inflection-of"})


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


def direct_glosses(entry: dict) -> list[str]:
    """Return English definitions stated directly on ``entry``'s senses.

    English Wiktionary defines Spanish headwords in English, so for that
    source the sense glosses *are* the card back -- no translation step and
    no MT. Inflection pointers ("plural of pie") are skipped: they describe a
    form rather than defining the word.
    """
    out: list[str] = []
    for sense in entry.get("senses") or []:
        if NON_LEMMA_TAGS & set(sense.get("tags") or []):
            continue
        for gloss in sense.get("glosses") or []:
            text = gloss.strip()
            if text and not _is_inflection_pointer(text) and text not in out:
                out.append(text)
    return out


def _is_inflection_pointer(gloss: str) -> bool:
    """Whether ``gloss`` merely points at another headword.

    Only *pure* pointers are rejected -- "plural of pie" defines nothing on
    its own. A gloss that names the relation and then gives the meaning
    ("accusative of yo: me") is a real definition and must be kept, otherwise
    the commonest pronouns in any song fall through to a worse source.
    """
    lowered = gloss.lower().strip()
    if ":" in lowered or ";" in lowered:
        return False
    markers = (
        "singular",
        "plural",
        "participle",
        "indicative",
        "subjunctive",
        "imperative",
        "gerund",
        "feminine",
        "masculine",
    )
    return " of " in lowered and any(m in lowered for m in markers)


def source_gloss(entry: dict) -> str:
    """Return the first source-language definition in ``entry``."""
    for sense in entry.get("senses") or []:
        # Skip senses that only say "plural of X" -- those are inflection
        # pointers, not definitions, and make a useless card back.
        if NON_LEMMA_TAGS & set(sense.get("tags") or []):
            continue
        for gloss in sense.get("glosses") or []:
            if gloss.strip():
                return gloss.strip()
    return ""


def is_lemma_entry(entry: dict) -> bool:
    """Whether ``entry`` is a headword rather than an inflected form."""
    tags = set(entry.get("tags") or [])
    if NON_LEMMA_TAGS & tags:
        return False
    return bool(entry.get("word")) and bool(entry.get("pos"))


# A sense longer than this reads as an encyclopaedia entry rather than a card
# back. Measured across the 125,481-lemma Spanish pack: only 80 lemmas have
# any sense this long, and 8 exceed 300 characters. `gustar`'s first sense is
# 334 characters of grammar commentary ("analyzable in structure as...",
# "Compare similar structures in Italian piacere...") while its remaining
# three senses are the actual translations.
MAX_SENSE_CHARS = 200


def split_senses(gloss: str) -> list[str]:
    """Split a joined gloss on top-level ``"; "`` separators.

    Parenthesised text is *not* split: place-name glosses embed semicolons
    inside their parenthetical ("Danube (a river in Europe; flowing 2,850
    kilometers...)"), and a naive ``str.split`` cuts mid-parenthetical and
    leaves an unbalanced fragment reading "Danube (a river in Europe".
    """
    senses: list[str] = []
    current: list[str] = []
    depth = 0
    index = 0
    while index < len(gloss):
        char = gloss[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        if depth == 0 and gloss.startswith("; ", index):
            senses.append("".join(current))
            current = []
            index += 2
            continue
        current.append(char)
        index += 1
    if current:
        senses.append("".join(current))
    return senses


def trim_long_senses(gloss: str) -> str:
    """Drop senses too long to read on a card back.

    Never returns empty: when *every* sense is over-long (49 lemmas, all
    proper names) the shortest is kept, because dropping the last sense would
    delete the card rather than shorten it.
    """
    senses = split_senses(gloss)
    kept = [sense for sense in senses if len(sense) <= MAX_SENSE_CHARS]
    if not kept:
        if not senses:
            return gloss
        kept = [min(senses, key=len)]
    return "; ".join(kept)
