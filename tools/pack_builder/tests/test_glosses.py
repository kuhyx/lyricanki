"""Tests for extracting card-ready glosses from a kaikki entry."""

from __future__ import annotations

from glosses import (
    MAX_SENSE_CHARS,
    direct_glosses,
    english_glosses,
    is_lemma_entry,
    source_gloss,
    split_senses,
    trim_long_senses,
)


def _entry(**kwargs: object) -> dict:
    base = {"word": "amor", "pos": "noun", "lang_code": "es", "senses": []}
    base.update(kwargs)
    return base


def test_direct_glosses_keeps_a_real_definition() -> None:
    entry = _entry(senses=[{"glosses": ["love; love affair"]}])
    assert direct_glosses(entry) == ["love; love affair"]


def test_direct_glosses_drops_a_pure_inflection_pointer() -> None:
    """"plural of pie" defines nothing; it points at another headword."""
    entry = _entry(senses=[{"glosses": ["plural of pie"]}])
    assert direct_glosses(entry) == []


def test_direct_glosses_keeps_a_pointer_that_also_defines() -> None:
    """`me` is glossed "accusative of yo: me" -- that IS the definition."""
    entry = _entry(senses=[{"glosses": ["accusative of yo: me"]}])
    assert direct_glosses(entry) == ["accusative of yo: me"]


def test_direct_glosses_skips_form_of_senses() -> None:
    entry = _entry(senses=[{"glosses": ["x"], "tags": ["form-of"]}])
    assert direct_glosses(entry) == []


def test_english_glosses_reads_the_translation_list() -> None:
    entry = _entry(
        translations=[
            {"lang_code": "en", "word": "love"},
            {"lang_code": "fr", "word": "amour"},
            {"lang_code": "en", "word": "love"},
        ]
    )
    assert english_glosses(entry) == ["love"]


def test_source_gloss_returns_the_first_definition() -> None:
    entry = _entry(senses=[{"glosses": ["Sentimiento intenso."]}])
    assert source_gloss(entry) == "Sentimiento intenso."


def test_source_gloss_is_empty_without_senses() -> None:
    assert source_gloss(_entry()) == ""


def test_is_lemma_entry_rejects_an_inflected_form() -> None:
    assert not is_lemma_entry(_entry(tags=["form-of"]))
    assert not is_lemma_entry({"word": "x"})
    assert is_lemma_entry(_entry())


def test_source_gloss_skips_an_inflection_sense() -> None:
    """A `form-of` sense is a pointer, so it must not become the definition."""
    entry = _entry(
        senses=[
            {"glosses": ["plural of amor"], "tags": ["form-of"]},
            {"glosses": ["Sentimiento."]},
        ]
    )
    assert source_gloss(entry) == "Sentimiento."



def test_direct_glosses_exhausts_senses_without_a_usable_gloss() -> None:
    entry = _entry(senses=[{"glosses": ["plural of x"]}, {"glosses": [""]}])
    assert direct_glosses(entry) == []


def test_english_glosses_skips_entries_without_a_word() -> None:
    entry = _entry(translations=[{"lang_code": "en", "word": ""}])
    assert english_glosses(entry) == []


def test_direct_glosses_scans_every_gloss_of_a_sense() -> None:
    """A sense can hold several glosses; all are collected in order."""
    entry = _entry(senses=[{"glosses": ["love", "affection"]}])
    assert direct_glosses(entry) == ["love", "affection"]


def test_direct_glosses_skips_a_blank_gloss_and_continues() -> None:
    entry = _entry(senses=[{"glosses": ["", "love"]}])
    assert direct_glosses(entry) == ["love"]


def test_direct_glosses_deduplicates_repeated_text() -> None:
    entry = _entry(senses=[{"glosses": ["love"]}, {"glosses": ["love"]}])
    assert direct_glosses(entry) == ["love"]


def test_source_gloss_exhausts_all_senses_without_a_definition() -> None:
    """Every sense is a pointer or blank, so the loop runs to completion."""
    entry = _entry(
        senses=[
            {"glosses": ["plural of x"], "tags": ["form-of"]},
            {"glosses": [""]},
            {},
        ]
    )
    assert source_gloss(entry) == ""


class TestSplitSenses:
    """``split_senses`` divides a joined gloss without breaking parentheses."""

    def test_splits_on_top_level_separator(self) -> None:
        assert split_senses("to run; to flow") == ["to run", "to flow"]

    def test_keeps_semicolons_inside_parentheses(self) -> None:
        # Danube's gloss embeds "; flowing 2,850 kilometers" inside its
        # parenthetical; splitting there leaves "Danube (a river in Europe".
        gloss = "Danube (a river in Europe; flowing far); a waltz"
        assert split_senses(gloss) == [
            "Danube (a river in Europe; flowing far)",
            "a waltz",
        ]

    def test_empty_gloss_yields_no_senses(self) -> None:
        assert split_senses("") == []

    def test_unbalanced_closing_paren_does_not_go_negative(self) -> None:
        # A stray ")" must not push depth below zero, which would make every
        # later separator look nested and stop splitting entirely.
        assert split_senses("a); b") == ["a)", "b"]


class TestTrimLongSenses:
    """``trim_long_senses`` drops encyclopaedic senses, never the card."""

    def test_keeps_ordinary_glosses_unchanged(self) -> None:
        assert trim_long_senses("love; love affair") == "love; love affair"

    def test_drops_the_over_long_sense_and_keeps_the_rest(self) -> None:
        # This is the `gustar` shape: a grammar essay followed by the real
        # translations.
        essay = "x" * (MAX_SENSE_CHARS + 1)
        gloss = f"{essay}; to like romantically"
        assert trim_long_senses(gloss) == "to like romantically"

    def test_keeps_the_shortest_when_every_sense_is_long(self) -> None:
        # 49 lemmas (all proper names) are entirely over-long; dropping the
        # last sense would delete the card instead of shortening it.
        longer = "y" * (MAX_SENSE_CHARS + 10)
        shorter = "z" * (MAX_SENSE_CHARS + 1)
        assert trim_long_senses(f"{longer}; {shorter}") == shorter

    def test_empty_gloss_is_returned_unchanged(self) -> None:
        assert trim_long_senses("") == ""
