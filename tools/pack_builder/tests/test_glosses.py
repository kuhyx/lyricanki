"""Tests for extracting card-ready glosses from a kaikki entry."""

from __future__ import annotations

from glosses import (
    direct_glosses,
    english_glosses,
    is_lemma_entry,
    source_gloss,
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
