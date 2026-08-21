"""Tests for diminutive and elision recovery."""

from __future__ import annotations

from morphology import diminutive_bases, elision_bases, recover


def test_recovers_the_song_title() -> None:
    """`despacito` is the acceptance song's own title: it must card."""
    assert recover("despacito", lambda s: s == "despacio") == "despacio"


def test_recovers_a_c_infix_diminutive() -> None:
    assert recover("suavecito", lambda s: s == "suave") == "suave"


def test_recovers_a_sung_elision() -> None:
    assert recover("vamo", lambda s: s == "vamos") == "vamos"


def test_returns_none_when_no_base_is_known() -> None:
    assert recover("despacito", lambda _: False) is None


def test_never_yields_the_surface_itself() -> None:
    assert "ito" not in list(diminutive_bases("ito"))


def test_ignores_a_stem_too_short_to_be_a_word() -> None:
    assert list(diminutive_bases("mito")) == []


def test_elision_only_applies_to_mo_endings() -> None:
    assert list(elision_bases("casa")) == []
    assert list(elision_bases("vamo")) == ["vamos"]


def test_diminutive_loop_exhausts_all_endings() -> None:
    """No base ending produces a known word, so recovery must give up."""
    assert recover("zzzzito", lambda _s: False) is None


def test_recover_falls_through_to_elision_when_no_diminutive() -> None:
    assert recover("vamo", lambda s: s == "vamos") == "vamos"


def test_recover_returns_none_when_neither_rule_applies() -> None:
    assert recover("corazón", lambda _s: True) is None


def test_recover_rejects_an_elision_candidate_that_is_unknown() -> None:
    """`vamo` yields `vamos`, but if the pack lacks it recovery must fail.

    This walks the elision loop to exhaustion rather than exiting early,
    which the other cases never do.
    """
    assert recover("vamo", lambda _s: False) is None


def test_diminutive_generator_skips_duplicate_candidates() -> None:
    """`solecito` matches both `cito` and `ecito`, yielding `sole` twice.

    The second must be skipped, or the same base is looked up repeatedly.
    """
    bases = list(diminutive_bases("solecito"))
    assert bases.count("sole") == 1
    assert len(bases) == len(set(bases))


def test_diminutive_skips_a_short_stem_and_keeps_scanning() -> None:
    """`ito` has too short a stem; the loop must continue to later suffixes."""
    assert list(diminutive_bases("ito")) == []
