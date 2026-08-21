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
