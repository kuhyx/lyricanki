# lyricanki — next session prompt

Paste everything below the line into a fresh Claude session with cwd `~/lyricanki`.

---

Work on `~/lyricanki`. Read `/home/kuhy/.claude/plans/learn-language-through-the-zany-boole.md`
first — it is the approved plan and records every settled decision (Q1–Q21). This file is the
handoff from the session that built M0–M2.

## State: what already works

4 commits on `main`, working tree clean, **nothing pushed yet** (no GitHub remote).

- **M0 scaffold** — Flutter app composed from `~/todo` + `~/habit_stack`. `scripts/ci_mirror.sh`
  is green end to end (analyze → format → 15 Dart tests → 100% coverage gate). This is the
  first of kuhy's app repos with a real coverage gate rather than discipline.
- **M1 tokenizer** (`lib/services/pipeline/tokenizer.dart`) — verified to reproduce the Python
  measurement exactly: 77 lines / 472 tokens / 183 unique surfaces on the pinned song.
- **M2 pack builder** (`tools/pack_builder/`, Python, never shipped) — 67 tests at **100%
  branch coverage**, no suppressions. Builds `lyricanki-es.sqlite` (**42.9 MB**, gitignored)
  in ~25 s; resolves the whole song in **5 ms**.

**Measured result: 148 cards, zero empty glosses**, on pinned LRCLIB track `36856755`
(Luis Fonsi, 273 s). The only unresolved tokens are 7 non-Spanish ones: 4 ad-libs
(`dididiri`, `fonsi`, `ohhh`, `woah`) and 3 English loanwords (`yeah`, `bang`, `daddy`).

Rebuild the pack (inputs are gitignored, ~1.1 GB, re-download if absent — see
`tools/pack_builder/README.md`):

```bash
cd ~/lyricanki/tools/pack_builder
python3 build_pack.py --extract downloads/es-en-wiktionary.jsonl \
  --extract downloads/es-extract.jsonl.gz --output lyricanki-es.sqlite --language es
python3 -m pytest tests/ --cov --cov-report=term-missing   # must stay at 100%
```

## Two corrections already applied — do not re-derive

1. **The card count is 148, not 143.** 143 came from `simplemma` + a `wordfreq` proxy; the app
   resolves through the pack's `forms` table, a *different lemmatizer*. 148 is measured
   end to end. (An earlier ≥150 was also wrong — under 150 lemmas exist.)
2. **Only the first extract may supply `gloss_en`.** English Wiktionary defines Spanish words
   in English (`amor` → "love; love affair"); the per-language `es-extract` defines them in
   Spanish, and treating those as English produced cards reading "Corazón." for *corazón*.
   Offline MT was measured and **rejected** (`suave` → "Lack of dupurities and stammies").

Four classes of *wrong* card were found and fixed, each of which passes a "gloss is non-empty"
check — keep them working (`tools/pack_builder/ranking.py`, `enclitics.py`, `morphology.py`):
`amor` must not be the surname *Amor*; `me` must not be the initialism for "brain death";
`las` must not be German *lesen*; `dámelo` must be **dropped**, not carded as the name *Dame*.

---

# Tasks, in this order

## 1. M0 leftovers (quick, unblocks CI)

- `gh repo create kuhyx/lyricanki --public --source=. --push` (repo is public per kuhy's
  convention — verify against `reference-all-repos-are-public` memory first).
- Set the four release-signing secrets, or `release-apk.yml` fails on first push:
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD` (`gh secret set`; keystore at `~/.android/release/kuhy-release.jks`
  per the `reference-android-release-signing` memory).
- `bash scripts/install_hooks.sh` — pre-commit has never actually gated a commit here.
- Launcher icon via the `app-icon` skill: add a glyph to
  `~/testsAndMisc/python_pkg/app_icons/glyphs.py`, register
  `AppIcon(key="lyricanki", repo=_HOME/"lyricanki", accent="#B8862E", ...)` in `apps.py`, then
  `PYTHONPATH=~/testsAndMisc python3 -m python_pkg.app_icons generate --app lyricanki --android`
  and `dart run flutter_launcher_icons`. **An app shipping the stock Flutter icon is not done.**

## 2. M3 — the `.apkg` writer (pure Dart)

**Prove the Android SQLite write path on-device BEFORE building UI on top of it.** Writing a
SQLite file to an Android path is the one piece of the format work never verified; everything
else below was probed against real Anki output during planning.

Format (all verified, reproduce with `sqlite3` + `archive` + `crypto`):

- Zip contains **exactly two entries**: `collection.anki2` and `media` (literal `{}`). No audio.
- Schema **`ver = 11`** (legacy `.anki2`). AnkiDroid still imports it. No zstd, no `anki21b`.
- Tables `col`, `notes`, `cards`, `revlog`, `graves`. `col.models` / `col.decks` are JSON
  blobs; `col.decks` must also carry the default deck `"1"`.
- `notes.flds` = fields joined by **`\x1f`**. Fields: `Word` / `POS` / `Gloss` / `Line`.
- `notes.guid` = **base91 of the first 8 bytes of SHA-256(key)** over Anki's 91-char table —
  *not* sha1, *not* standard base64. Key is `es|<lemma>` (Q19: one card per word per language).
- `notes.csum` = `int(sha1_hex(first_field)[:8], 16)`. **genanki writes 0 here; we must populate
  it** — AnkiDroid uses csum for duplicate detection, which is the "updates in place, does not
  duplicate" half of the done condition.
- New cards = `type=0, queue=0, due=0`. **Model and deck ids are hardcoded constants**, never
  regenerated, or every export creates a fresh note type.

Done: output opens in desktop Anki *and* generates on-device; golden test asserts the zip
entries, `ver=11`, and guid + csum for a known lemma.

## 3. M4 — UI, then THE DONE CONDITION

LRCLIB search (`https://lrclib.net/api/search?q=`, `/api/get/{id}`, no key, set a real
User-Agent), a track picker that **must let you select `36856755`** (a bare "Despacito" search
returns 20 rows including the Bieber remix, which has English verses), a pack-download screen
carrying **CC BY-SA attribution** for kaikki/Wiktionary and credit to LRCLIB, a review screen
that lets the user uncheck words before export (Q3 — choice, not a filter), and export.

**The done condition** (on the phone `23181JEGR08034`, via the `phone-deploy` skill —
`adb install -r`, never uninstall or `pm clear`): search "Despacito", select track `36856755`,
generate, export `despacito.apkg`, import into AnkiDroid and get **exactly 148 notes**, one per
unique Spanish lemma, each carrying word / POS / gloss / its lyric line, with **zero** notes
whose gloss is empty or equal to the word — then **re-generate and re-import and confirm the
count is unchanged with no duplicates**.

The count must come from a committed fixture test, not a magic literal. `test/fixtures/
despacito_36856755.json` already holds the pinned track id, a SHA-256 of the lyrics and the
expected counts — **but its `expected_notes` still says 143 and must be updated to 148.**
Q8 forbids committing lyrics, so the fixture stores a hash, and the test fetches LRCLIB and
verifies the hash still matches before asserting the count.

## 4. The `estar` gap — kuhy's instruction, with a caveat to raise

kuhy's instruction, verbatim: *"when that happens use a LOCAL LLM HOSTABLE ON THE PHONE (small
enough that it works on pixel 6a)"*.

**Raise this before implementing.** The current gap is `estar`'s conjugations (`está`, `estás`,
`estaba`) — the kaikki extract has **zero forms** for that verb, though it has 141 for `ir` and
55 for `ser`; only 59.6% of verbs carry any inflected form. That is a **closed morphological
problem**: Spanish conjugation is fully regular given the verb class plus a short irregular
list, so a deterministic conjugator is a few hundred lines, always correct, instant, and adds
nothing to the APK. An LLM would be larger, slower, and occasionally wrong at something a table
gets right every time.

Recommended split, to put to kuhy rather than decide unilaterally:

- **Missing inflected forms → deterministic conjugator** (first-line fix; closes `estar`).
- **Missing gloss for a genuinely unknown word → small local LLM.** This is where an LLM
  actually earns its place, and it is the right answer for the long tail once packs exist for
  five languages. Pixel 6a (Tensor G1, 6 GB RAM) realistically runs a ~1 B-parameter model
  quantised to 4-bit (~700 MB) via `llama.cpp`/MediaPipe LLM Inference. Note this collides with
  Q12's "app ships with zero dictionaries" premise and adds ~700 MB to the install, so it needs
  an explicit decision about bundling vs downloading on demand.

If kuhy confirms the LLM route for glosses anyway, treat the model as a downloadable pack
alongside the dictionary pack, never bundled in the APK.

## 5. Q20's invariant is unsatisfiable as worded — needs a decision

Q20 says "expand the pack until no real word is missing". The remaining gaps are **upstream
data absences**, not pruning artifacts: no pack size conjures conjugations kaikki does not
contain. Current pruning is *not* a top-N frequency cut (frequency cannot distinguish a rare
real word from an unusable entry); it drops lemmas with no English gloss, which is both
smaller and strictly more accurate. Either reword Q20 to match, or accept the conjugator +
LLM fallback as the mechanism that satisfies its intent.

---

## Standing rules that bit during M0–M2

- **250-line cap applies to tests and prose too**, with no allowlist. `test_build_pack.py` hit
  306 lines and had to be split; `README.md` / `CLAUDE.md` count as well.
- **Branch coverage, not line coverage.** `pyproject.toml` sets `fail_under = 100` with
  `branch = true`. One genuinely unreachable branch was **deleted, not suppressed** — keep that
  standard; ask before adding any `# noqa` / `pragma: no cover`.
- Verify a claim before making it. Two agreed acceptance numbers (≥150, then 143) were both
  wrong on measurement, and both would have failed on the phone rather than in a test.
