# lyricanki pack builder

Developer tool. Turns kaikki.org Wiktionary extracts into the SQLite
dictionary pack the app downloads. **Never shipped with the app.**

## Build the Spanish pack

```bash
cd tools/pack_builder
mkdir -p downloads
curl -o downloads/es-en-wiktionary.jsonl \
  https://kaikki.org/dictionary/Spanish/kaikki.org-dictionary-Spanish.jsonl
curl -o downloads/es-extract.jsonl.gz \
  https://kaikki.org/dictionary/downloads/es/es-extract.jsonl.gz
python3 build_pack.py \
  --extract downloads/es-en-wiktionary.jsonl \
  --extract downloads/es-extract.jsonl.gz \
  --output lyricanki-es.sqlite --language es
```

Takes ~25s and produces a 42.9 MB pack (125,481 lemmas, 1,257,656 forms).

**Source order matters.** Only the *first* extract may supply `gloss_en`.
English Wiktionary defines Spanish words in English (`amor` -> "love; love
affair"); the per-language `es-extract` defines them in Spanish, and treating
those as English produced cards reading "Corazón." for *corazón*. The second
source is there for its much richer inflected `forms`.

The 979 MB English-Wiktionary file is marked DEPRECATED upstream. Snapshot it
and record the date; if it disappears the fallback is the current path plus
machine translation, accepting worse glosses.

## Why the pack is 42.9 MB and not 221 MB

Three cuts, none of which lose a card:

| cut | saved |
|---|---|
| drop lemmas with no English gloss (and their forms) | 71 MB |
| drop the `tags` column -- nothing reads it | 68 MB |
| drop indexes duplicating a `WITHOUT ROWID` primary key | 39 MB |

## Tests

```bash
python3 -m pytest tests/ --cov --cov-report=term-missing
```

67 tests, 100% branch coverage, no suppressions.
