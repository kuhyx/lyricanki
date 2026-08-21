"""Tests for Spanish enclitic pronoun splitting."""

from __future__ import annotations

import pytest

from enclitics import PRONOUNS, resolve, split_enclitics, strip_to_known


def test_pronouns_are_longest_first() -> None:
    """`melo` must be tried before `me`, or `dámelo` splits wrongly."""
    assert PRONOUNS.index("melo") < PRONOUNS.index("me")


@pytest.mark.parametrize(
    ("surface", "stem"),
    [
        ("hacerlo", "hacer"),
        ("pensarlo", "pensar"),
        ("montarlo", "montar"),
    ],
)
def test_splits_simple_clusters(surface: str, stem: str) -> None:
    assert (stem, surface[len(stem):]) in split_enclitics(surface)


def test_deaccents_the_stem() -> None:
    """Attaching a pronoun adds a written accent the bare form lacks."""
    assert ("pensando", "lo") in split_enclitics("pensándolo")
    assert ("baila", "lo") in split_enclitics("báilalo")


def test_rejects_a_stem_too_short_to_be_a_verb() -> None:
    assert split_enclitics("los") == []


def test_returns_empty_when_no_pronoun_suffix() -> None:
    assert split_enclitics("corazón") == []


def test_strip_to_known_returns_first_accepted_stem() -> None:
    assert strip_to_known("hacerlo", lambda s: s == "hacer") == "hacer"


def test_strip_to_known_returns_none_when_nothing_matches() -> None:
    assert strip_to_known("hacerlo", lambda _: False) is None


def test_strip_to_known_rejects_a_non_callable() -> None:
    with pytest.raises(TypeError):
        strip_to_known("hacerlo", "not callable")


def test_resolve_prefers_the_verb_reading() -> None:
    def lookup(stem: str) -> list[tuple[str, str]]:
        return [("Hacer", "noun"), ("hacer", "verb")] if stem == "hacer" else []

    assert resolve("hacerlo", lookup) == ("hacer", "hacer", "verb")


def test_resolve_refuses_a_non_verb_match() -> None:
    """`dámelo` matches the proper noun "Dame"; carding it would be WRONG.

    A wrong gloss still passes a "gloss is non-empty" check, so the only safe
    answer is to drop the word.
    """

    def lookup(stem: str) -> list[tuple[str, str]]:
        return [("Dame", "noun")] if stem == "dame" else []

    assert resolve("dámelo", lookup) is None


def test_resolve_returns_none_when_lookup_is_empty() -> None:
    assert resolve("hacerlo", lambda _: []) is None


def test_resolve_rejects_a_non_callable() -> None:
    with pytest.raises(TypeError):
        resolve("hacerlo", object())


def test_split_tries_every_pronoun_before_giving_up() -> None:
    """Exhausting the pronoun list must fall through, not hang or match."""
    assert split_enclitics("corazon") == []


def test_resolve_exhausts_all_splits_before_returning_none() -> None:
    """`selo`/`se`/`lo` all match `dselo`; none resolves to a verb."""
    assert resolve("dámeselo", lambda _s: [("X", "noun")]) is None


def test_resolve_walks_every_candidate_row_of_a_split() -> None:
    """A split whose rows hold no verb must keep trying later splits.

    Two non-verb rows force the inner loop to run to completion rather than
    returning on the first row.
    """
    assert resolve(
        "hacerlo",
        lambda s: [("a", "noun"), ("b", "adj")] if s == "hacer" else [],
    ) is None


def test_split_continues_past_a_pronoun_that_does_not_match() -> None:
    """`bailalo` ends in `lo` but not `melo`; earlier misses must not stop."""
    splits = split_enclitics("bailalo")
    assert ("baila", "lo") in splits


def test_split_does_not_repeat_an_identical_stem_and_pronoun() -> None:
    """An unaccented stem equals its own de-accented variant.

    `_candidate_stems` then yields the same string twice, and the second must
    not be appended, or the caller looks the same stem up repeatedly.
    """
    splits = split_enclitics("hacerlo")
    assert splits.count(("hacer", "lo")) == 1
