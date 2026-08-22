> **This file is a ready-to-use prompt.** Open `~/lyricanki` and say
> "do exported-song-history". It is self-contained.
>
> Written 2026-08-22 from a user report. Every claim below was checked against
> the tree that day; **re-verify before trusting it**, since the repo moves.

## ⛔ WHEN YOU FINISH

Delete this file and commit the deletion with the work:

```bash
git rm prompts/exported-song-history.md
```

A finished prompt is indistinguishable from a pending one, and the next
session will re-run it.

## The report

> "After the song gets done I would like to see it in a list. Right now
> lyricanki shows an empty ready screen as if nothing was done (it was the
> despacito song that was done)."

## What is actually wrong -- read this before writing code

**This is not a display bug, and nothing regressed.** The app has *no
persistence of exported songs at all*. Checked on 2026-08-22:

```bash
grep -rniE "history|completed|finished|exported" lib --include='*.dart'
```

returns exactly one hit, and it is the transient status string in
`lib/screens/song_search_screen.dart` (`'Exported N cards ... to <path>'`).
The only things the app persists are the dictionary pack
(`lib/services/pack/pack_store.dart`) and the `.apkg` files themselves
(`lib/services/export_destination.dart`). `DeckSession` is a `ChangeNotifier`
held in memory for one song and then dropped.

So the screen is empty because there is nothing to show it -- **you are
building a feature, not fixing a regression.** Do not go looking for a broken
query.

The user's word "ready" is their name for the home screen, which is
`SongSearchScreen` (`lib/main.dart` sets `home: const SongSearchScreen()`).
There is no screen called "ready" in the codebase; don't hunt for one.

**It is also not in the approved plan.** `/home/kuhy/.claude/plans/
learn-language-through-the-zany-boole.md` records settled decisions Q1-Q21 and
contains no history/library item. This is new scope, so the design questions
below are genuinely open -- ask them, do not assume.

## Ask these before building

The user asked for "a list". That leaves real forks. Ask them as one
`AskUserQuestion` round, with a recommendation each, then build:

1. **What does tapping an entry do?** Nothing (a record); re-open the share
   sheet for the existing `.apkg`; or rebuild the deck from the track.
   *Recommended: re-share the existing file* -- it is the cheapest and matches
   why the share sheet exists at all (from API 30 the storage picker cannot
   browse into `Android/data`, so a path alone is unusable).
2. **Where does the list live?** A section on `SongSearchScreen` below the
   search field, or a separate screen behind an app-bar icon next to the
   existing `Icons.storage_outlined` pack button. *Recommended: a section on
   the home screen* -- it is what "shows an empty ready screen" implies they
   expect to see filled in.
3. **What happens when the `.apkg` is gone** (user deleted it, or Android
   cleared external app storage)? Hide the entry, or show it greyed with the
   file missing. *Recommended: show it, disabled* -- silently vanishing
   history is worse than a dead row, and the export still happened.
4. **Re-exporting the same track**: one entry updated in place, or two rows?
   *Recommended: update in place*, keyed by track identity, most recent first.

## Where the code goes

- **New:** `lib/services/export_history.dart` -- the store. Follow
  `lib/services/pack/pack_store.dart` for the on-disk conventions and
  `lib/services/export_destination.dart` for the `directoryOverride`
  test-seam pattern. **Copy that seam**: its comment says it exists so "a test
  run can never write into the live app's export directory", and the same
  hazard applies here.
- **New:** a widget for the list; put it under `lib/screens/` or
  `lib/widgets/` consistently with what exists when you look.
- **Changed:** `lib/screens/song_search_screen.dart` -- record on successful
  export, inside `_export`, *after* `session.export(path)` returns. Recording
  before the write would list songs that failed to export.
- **Consider:** `lib/models/` for the entry type, matching `track.dart`'s
  style (immutable, documented fields).

Store at minimum: track name/artist, the `.apkg` path, the card count, and a
timestamp. `Track` (`lib/models/track.dart`) already carries the identity --
reuse it rather than inventing a parallel one.

## Hard rules in this repo

These are from `NEXT_SESSION.md` and bit previous sessions:

- **Branch coverage with `fail_under = 100`, and no suppressions.** New code
  needs tests, including the failure paths.
- **250-line cap on every file, tests and prose included.** Plan the split up
  front rather than discovering it at commit time.
- **Real `dart:io` deadlocks `testWidgets`** -- use `tester.runAsync` or keep
  setup synchronous. `test/screens/flow_harness.dart` already wraps this.
- **`pumpAndSettle` never returns** while an indeterminate progress bar
  animates.
- **Never open a GUI on the user's monitors** -- use `scripts/run_headless.sh`
  (Xvfb + xdotool).
- **Wrap builds in `scripts/capped_run.sh`**, or use `phone_deploy.sh`.
- **`phone_deploy.sh` can exit 0 while the build failed.** Check the log tail
  for `exit 34`, or the APK's mtime. A task notification saying "success" has
  been wrong with a 20-minute-stale APK.
- Theming comes entirely from `design_system`; there is deliberately no local
  `theme.dart`. Do not invent colours or spacing.

## Done when

- A song exported through the normal flow appears in the list, and is still
  there after a full app restart (not just a hot reload -- that would prove
  nothing about persistence).
- The list survives the case the user hit: **export "Despacito", kill the app,
  reopen it, and the entry is there.** Use that exact song, since it is the
  one they reported.
- `flutter test` green with 100% branch coverage and no suppressions.
- `dart analyze` clean.

## Verify

On the phone (Pixel 6a, Android 16 / SDK 36), not only on desktop -- mobile is
the primary platform for this app, and the two have already diverged twice
here (the missing INTERNET permission in release builds, and exports landing
where nothing could read them). Deploy with `phone_deploy.sh`, then export a
song, force-stop the app, reopen it, and confirm the entry is listed.

Report what you saw on the device. Per the repo's own standing note: three
agreed acceptance numbers were each wrong on measurement, so state the
observation, not the expectation.
