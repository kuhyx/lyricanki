"""Spanish morphology rules that recover words Wiktionary does not list.

Two gaps show up immediately in song lyrics and neither is a pruning artifact
-- no pack size fixes them, because the source extract simply has no entry:

* **Diminutives.** ``despacito`` (the song title) and ``suavecito`` are absent;
  their bases ``despacio`` and ``suave`` are present with English glosses.
* **Colloquial elision.** Sung Spanish drops the final *s* of the first person
  plural: ``vamo`` for ``vamos``.

Each rule is only applied when the rewritten form is already known to the
pack, so a rule can recover a word but never invent one.
"""

from __future__ import annotations

from collections.abc import Callable, Iterator

# Diminutive suffixes, paired with the endings the base may take. Spanish
# inserts -c- before the suffix after certain stems (suave -> suavecito), so
# both the plain and -c- forms are tried.
_DIMINUTIVE_SUFFIXES = (
    "ito",
    "ita",
    "itos",
    "itas",
    "cito",
    "cita",
    "citos",
    "citas",
    "ecito",
    "ecita",
)
_BASE_ENDINGS = ("o", "a", "e", "io", "ia", "")


def diminutive_bases(surface: str) -> Iterator[str]:
    """Yield plausible base forms for the diminutive ``surface``."""
    seen: set[str] = set()
    for suffix in _DIMINUTIVE_SUFFIXES:
        if not surface.endswith(suffix):
            continue
        stem = surface[: -len(suffix)]
        if len(stem) < 3:
            continue
        for ending in _BASE_ENDINGS:
            candidate = stem + ending
            if candidate and candidate != surface and candidate not in seen:
                seen.add(candidate)
                yield candidate


def elision_bases(surface: str) -> Iterator[str]:
    """Yield base forms for colloquially elided ``surface`` (``vamo``)."""
    # -mos -> -mo is the common sung elision; restoring the s is safe because
    # the result must still be a known form to be accepted.
    if surface.endswith("mo"):
        yield surface + "s"


def recover(surface: str, is_known: Callable[[str], bool]) -> str | None:
    """Return a known base for ``surface``, or ``None``.

    Diminutives are tried before elisions because they are far more common in
    lyrics and cannot overlap: no diminutive suffix ends in ``mo``.
    """
    for candidate in diminutive_bases(surface):
        if is_known(candidate):
            return candidate
    for candidate in elision_bases(surface):
        if is_known(candidate):
            return candidate
    return None
