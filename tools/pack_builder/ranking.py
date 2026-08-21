"""Pick the right dictionary entry when a surface form matches several.

Wiktionary stores proper nouns, initialisms and common words under the same
letters, so a naive "first row wins" turns the lyric ``amor`` into the surname
*Amor* and ``me`` into the initialism *ME* ("muerte encefálica"). Those are
wrong cards, and a wrong card still passes a "gloss is non-empty" check --
so the choice has to be made deliberately.
"""

from __future__ import annotations

from collections.abc import Callable

# Parts of speech that a lyric word is most likely to be, best first. Function
# words rank above nouns because the words that repeat in a song are
# overwhelmingly grammatical.
_POS_RANK = (
    "verb",
    "pron",
    "prep",
    "det",
    "article",
    "conj",
    "adv",
    "adj",
    "noun",
    "intj",
    "num",
)

# Parts of speech that are almost never what a singer meant.
_POS_PENALTY = frozenset({"name", "abbrev", "symbol", "character", "punct", "phrase"})


def _pos_score(pos: str) -> int:
    """Return a sort key for ``pos``: lower is a better candidate."""
    if pos in _POS_PENALTY:
        return len(_POS_RANK) + 10
    try:
        return _POS_RANK.index(pos)
    except ValueError:
        return len(_POS_RANK)


# Spanish function words that a lyric almost always uses in one specific
# sense. Wiktionary also lists rarer readings (`y` as a pronoun in Aragonese
# borrowings, `de` as a pronoun) that outrank the real one on POS alone, and
# the wrong reading is a wrong card. Pinning the handful of words that carry a
# song is cheaper and far more accurate than trying to rank POS generically.
_FUNCTION_WORD_POS = {
    "y": "conj",
    "o": "conj",
    "de": "prep",
    "a": "prep",
    "en": "prep",
    "con": "prep",
    "por": "prep",
    "para": "prep",
    "sin": "prep",
    "que": "pron",
    "me": "pron",
    "te": "pron",
    "se": "pron",
    "le": "pron",
    "lo": "pron",
    "la": "article",
    "el": "article",
    "un": "article",
    "una": "article",
    "mi": "det",
    "tu": "det",
    "su": "det",
    "no": "adv",
    "si": "conj",
    "ya": "adv",
    "mas": "conj",
    "más": "adv",
}


def rank_candidates(
    surface: str,
    candidates: list[tuple[str, str]],
    has_english: Callable[[str, str], bool] | None = None,
) -> list[tuple[str, str]]:
    """Order ``candidates`` for ``surface``, best first.

    A lowercase surface prefers a lowercase lemma: the singer wrote ``amor``,
    not the surname *Amor*.

    When ``has_english`` is given, a candidate that actually carries an
    English gloss outranks one that does not. The source file holds a few
    non-Spanish headwords under the same letters -- ``las`` also being German
    *lesen*, ``ti`` also meaning "to boil" -- and picking those produced a
    card with no usable back. Having a gloss is the strongest available signal
    that the entry is the one the singer meant.
    """
    surface_is_lower = surface == surface.lower()
    pinned = _FUNCTION_WORD_POS.get(surface.lower())

    def key(candidate: tuple[str, str]) -> tuple[int, int, int, int, str]:
        lemma, pos = candidate
        gloss_penalty = (
            0 if has_english is None or has_english(lemma, pos) else 1
        )
        case_penalty = 1 if surface_is_lower and lemma != lemma.lower() else 0
        pin_penalty = 0 if pinned is not None and pos == pinned else 1
        return (gloss_penalty, case_penalty, pin_penalty, _pos_score(pos),
                lemma)

    return sorted(candidates, key=key)


def best_candidate(
    surface: str,
    candidates: list[tuple[str, str]],
    has_english: Callable[[str, str], bool] | None = None,
) -> tuple[str, str] | None:
    """Return the single best entry for ``surface``, or ``None`` if empty."""
    ranked = rank_candidates(surface, candidates, has_english)
    return ranked[0] if ranked else None
