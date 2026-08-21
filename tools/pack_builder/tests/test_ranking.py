"""Tests for choosing between competing dictionary entries."""

from __future__ import annotations

from ranking import best_candidate, rank_candidates


def test_prefers_the_common_noun_over_a_surname() -> None:
    """`amor` in a lyric is "love", never the surname *Amor*."""
    best = best_candidate("amor", [("Amor", "name"), ("amor", "noun")])
    assert best == ("amor", "noun")


def test_prefers_a_word_over_an_initialism() -> None:
    best = best_candidate("me", [("ME", "noun"), ("me", "pron")])
    assert best == ("me", "pron")


def test_pins_function_words_to_their_lyric_sense() -> None:
    """`y` is the conjunction "and", not a rare pronoun reading."""
    best = best_candidate("y", [("y", "pron"), ("y", "conj")])
    assert best == ("y", "conj")


def test_prefers_a_candidate_that_has_an_english_gloss() -> None:
    """`las` also matches German *lesen*, which has no English gloss here."""
    candidates = [("lesen", "verb"), ("las", "article")]
    best = best_candidate(
        "las",
        candidates,
        has_english=lambda lemma, _pos: lemma == "las",
    )
    assert best == ("las", "article")


def test_gloss_preference_outranks_the_function_word_pin() -> None:
    """A pinned POS is useless if that entry cannot produce a card back."""
    best = best_candidate(
        "de",
        [("de", "prep"), ("de", "noun")],
        has_english=lambda _lemma, pos: pos == "noun",
    )
    assert best == ("de", "noun")


def test_penalises_names_and_symbols() -> None:
    ranked = rank_candidates("pa", [("Pa", "symbol"), ("pa", "prep")])
    assert ranked[0] == ("pa", "prep")


def test_unknown_parts_of_speech_sort_after_known_ones() -> None:
    ranked = rank_candidates("x", [("x", "wat"), ("x", "verb")])
    assert ranked[0] == ("x", "verb")


def test_returns_none_for_no_candidates() -> None:
    assert best_candidate("x", []) is None
