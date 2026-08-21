"""Split Spanish enclitic pronoun clusters off a verb form.

Spanish attaches object pronouns to infinitives, gerunds and imperatives:
``dámelo`` is *dar* + *me* + *lo*, ``pensándolo`` is *pensando* + *lo*.
Wiktionary lists these as separate entries only sporadically, so a pack built
straight from the extract fails on exactly the words a song is full of --
measured on Despacito, 16 of 24 unresolved surfaces were enclitic clusters.

This is deliberately conservative: a split is only accepted when the stripped
stem is a form the pack already knows. Guessing would invent lemmas.
"""

from __future__ import annotations

# Longest first: "melo" must be tried before "me" so `dámelo` splits cleanly.
PRONOUNS = (
    "melo",
    "mela",
    "melos",
    "melas",
    "telo",
    "tela",
    "telos",
    "telas",
    "selo",
    "sela",
    "selos",
    "selas",
    "noslo",
    "nosla",
    "noslos",
    "noslas",
    "oslo",
    "osla",
    "oslos",
    "oslas",
    "sele",
    "seles",
    "me",
    "te",
    "se",
    "nos",
    "os",
    "le",
    "les",
    "lo",
    "la",
    "los",
    "las",
)

# Attaching a pronoun shifts the stress, so Spanish adds a written accent that
# the bare verb form does not carry: dar -> dámelo, pensando -> pensándolo.
# Removing it is what makes the stem findable.
_DEACCENT = str.maketrans("áéíóú", "aeiou")


def _candidate_stems(stem: str) -> list[str]:
    """Return ``stem`` plus its unaccented variant, without duplicates."""
    plain = stem.translate(_DEACCENT)
    return [stem] if plain == stem else [stem, plain]


def split_enclitics(surface: str) -> list[tuple[str, str]]:
    """Return ``(stem, pronouns)`` splits of ``surface``, longest match first.

    Every plausible split is returned; the caller decides which stem actually
    exists in the pack. An empty list means no pronoun suffix was found.
    """
    results: list[tuple[str, str]] = []
    for pronoun in PRONOUNS:
        if not surface.endswith(pronoun):
            continue
        stem = surface[: -len(pronoun)]
        # A two-letter stem cannot be a Spanish verb form; without this,
        # "los" would "split" into an empty stem.
        if len(stem) < 3:
            continue
        for candidate in _candidate_stems(stem):
            entry = (candidate, pronoun)
            if entry not in results:
                results.append(entry)
    return results


def strip_to_known(surface: str, is_known: object) -> str | None:
    """Return the first split stem of ``surface`` that ``is_known`` accepts.

    ``is_known`` is any callable taking a candidate stem and returning whether
    the pack contains it. Returns ``None`` when nothing matches.
    """
    if not callable(is_known):  # pragma: no cover - defensive
        raise TypeError("is_known must be callable")
    for stem, _ in split_enclitics(surface):
        if is_known(stem):
            return stem
    return None


def resolve(surface: str, lookup: object) -> tuple[str, str, str] | None:
    """Resolve an enclitic cluster to ``(stem, lemma, pos)``.

    ``lookup`` takes a stem and returns its ``(lemma, pos)`` candidate rows.
    A verb reading always wins: only verbs take enclitic pronouns, so when
    ``dámelo`` also matches the proper noun "Dame" the verb is the correct
    answer, not merely the likelier one.
    """
    if not callable(lookup):  # pragma: no cover - defensive
        raise TypeError("lookup must be callable")
    for stem, _ in split_enclitics(surface):
        rows = list(lookup(stem) or [])
        for lemma, pos in rows:
            if pos == "verb":
                return (stem, lemma, pos)
    # No verb reading anywhere: refuse rather than card the noun. Only verbs
    # take enclitic pronouns, so a non-verb match means the split was wrong --
    # `dámelo` matches the proper noun "Dame", which would be a WRONG card,
    # and a wrong card still passes a "gloss is non-empty" check.
    return None
