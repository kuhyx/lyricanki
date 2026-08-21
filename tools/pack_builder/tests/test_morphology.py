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
