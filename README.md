# lyricanki

Turn a song into an Anki vocabulary deck: every unique word in the lyrics,
lemmatised, glossed from a real dictionary, with the lyric line it came from.

Pick a track, untick the words you already know, export a `.apkg`, import it
into Anki or AnkiDroid. Spanish today; the pack format is language-agnostic.

A card looks like this — word, part of speech, gloss, and the line it appeared
in:

| Field | Example |
| --- | --- |
| Word | `saber` |
| POS | `verb` |
| Gloss | `to know, to understand (a fact); to find out` |
| Line | `Quiero desnudarte a besos despacito` |

## Running it

```bash
flutter pub get
flutter run                       # desktop
flutter run -d <android-device>   # phone
```

On first launch the app has no dictionary. Tap the storage icon and download
the pack — 43 MB, published as a GitHub release asset, so nothing is hosted
and nothing is metered.

## Where things live

| Path | What |
| --- | --- |
| `lib/services/pack/` | Downloading, storing and reading the dictionary pack |
| `lib/services/pipeline/` | Tokenising lyrics and building cards |
| `lib/services/apkg/` | Writing the `.apkg`, including Anki's schema and note guids |
| `lib/screens/` | Search, track picker, review, pack management |
| `tools/pack_builder/` | Developer tool that builds the pack; never shipped |

Packs are downloaded into external app storage on Android
(`/sdcard/Android/data/com.kuhy.lyricanki/files/packs`) rather than the
app-private documents directory, so a 43 MB pack can be side-loaded with
`adb push` instead of pulled over the network on every test install. Exports
go to `files/exports` in the same place, for the same reason, and are handed
to AnkiDroid through the share sheet — from API 30 the storage picker cannot
browse into `Android/data`, so telling the user a path is not enough.

## Checks

```bash
./scripts/ci_mirror.sh            # analyze, format, tests, 100% line coverage
./scripts/phone_verify.sh         # build, install and side-load onto the phone
```

`ci_mirror.sh` is what CI runs. Coverage is a hard gate at 100% with no
suppressions, and every file is capped at 250 lines.

The pack builder has its own suite:

```bash
cd tools/pack_builder && python3 -m pytest
```

## Building a pack

See `tools/pack_builder/README.md`. Short version: it turns kaikki.org
Wiktionary extracts into SQLite, and the order of the extracts matters —
English Wiktionary must come first, because it is the one that defines Spanish
words *in English*.
