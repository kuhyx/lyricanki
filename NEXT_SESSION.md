# lyricanki — next session prompt

Paste everything below the line into a fresh Claude session with cwd `~/lyricanki`.

---

Work on `~/lyricanki`. Read `/home/kuhy/.claude/plans/learn-language-through-the-zany-boole.md`
first — it is the approved plan and records every settled decision (Q1–Q21).

## Android is verified. There is no known blocker.

The whole flow was walked on the real phone (Pixel 6a, Android 16 / SDK 36) on
2026-08-22: install → pack → search → track → export → **import into
AnkiDroid** → re-import. Desktop was already verified. Both halves are done.

## Two real bugs were found and fixed doing it

1. **The release APK had no INTERNET permission.** Flutter's scaffold declares
   it only in `android/app/src/{debug,profile}/AndroidManifest.xml`, so every
   release build shipped unable to reach the network and failed with
   `Failed host lookup: 'lrclib.net'`. It is now in `main/AndroidManifest.xml`.

   **This was the "emulator DNS blocker" the previous handoff described.** It
   was never an emulator problem, and the untried fixes listed there
   (`-http-proxy`, `-wipe-data`, an older image) would all have failed. The
   phone's shell resolved `lrclib.net` fine while the app could not — the same
   split, from the same cause. Reproduced on the phone with the old APK, gone
   with the new one.

2. **Exports were written where nothing could read them.**
   `getApplicationDocumentsDirectory()` is `/data/user/0/<pkg>/app_flutter` on
   Android: app-private, invisible to AnkiDroid, unreachable by `adb pull`
   without root. The export succeeded and was then unreachable by the only app
   it exists to feed. Exports now go to `files/exports` in external app
   storage (`lib/services/export_destination.dart`) **and** are handed to a
   share sheet (`lib/services/apkg_share.dart`) — from API 30 the storage
   picker cannot browse into `Android/data`, so the path alone is useless.
   AnkiDroid registers `ACTION_SEND` for `application/apkg`, so the sheet is
   the supported handoff.

## Measured on the device, not inferred

- Search returns real LRCLIB results; `#36856755` (Luis Fonsi, 4:33) is there.
- The review screen offers **Export 147 cards** — the expected count.
- The exported file pulled off the phone: **147 notes, 0 empty fields, 4
  fields each**, and importing it into the real desktop `anki` library gives
  147, with a re-import leaving it at 147.
- **In AnkiDroid**: first import added 146 notes (a stray tap had unticked
  `ey`); re-importing the corrected 147-card file reported *"147 notes found,
  1 new, 146 used to update existing"* and left **one** Despacito deck. That
  is the dedup guarantee, on-device, against a collection that already held
  the notes.

## What also had to change, outside this repo

`com.kuhy.lyricanki` was missing from the Focus Owner allowlist, so it
installed `installed=true hidden=true`: absent from the launcher and from
`pm list packages`, with `am start` reporting the activity did not exist. It
is fixed in `testsAndMisc` commit `98ca3ac5` (config.sh + regenerated
policy.json). **A new `com.kuhy.*` app will hit this again** — the symptom
looks like a broken install and is not one.

`~/testsAndMisc/phone_focus_mode/deploy.sh` is for the old *rooted* phone and
fails with "Could not get root shell". The Pixel is unrooted under Device
Owner; the policy ships as a bundled asset, so a whitelist change means
regenerating `policy.json` and reinstalling `focus_owner`.

## If you touch focus_owner

Its signer must match the installed APK or the installer wants to uninstall —
and Device Owner **cannot be re-provisioned on an unrooted Pixel without a
factory reset**. Compare `keytool -list` against `apksigner verify` before
building, pull the live APK as a rollback first, and use
`~/.claude/scripts/phone_deploy.sh`, which does the signer check for you.

AnkiDroid's all-files permission was granted with
`adb shell appops set com.ichi2.anki MANAGE_EXTERNAL_STORAGE allow`; revert
with `... default` if you want it back as it was. It had no collection before
this session — the import created its first one.

## State

Pushed to `github.com/kuhyx/lyricanki` (public). `scripts/ci_mirror.sh` green:
analyze clean, **262 tests, 730/730 lines (100%)**, every file under 250 lines.
`tools/pack_builder`: 82 tests, 100% branch, no suppressions. Pack released as
`pack-es-v1`; the pinned URL returns HTTP 200 / 44,974,080 bytes.

## Corrections — do not re-derive

1. **The count is 147**, not 148 or 143. The pack builder counts 148
   *(lemma, pos)* pairs; the app emits one card per *lemma*, and `tu` resolves
   under two parts of speech. Both numbers are right about different things.
2. **The `estar` gap does not exist.** kaikki has **128 forms** for `estar`
   and **82.8%** verb coverage. Do not build a conjugator for it.
3. **WikDict, FreeDict, dbnary, Apertium, dict.cc, dictionaryapi.dev are all
   rejected** — measured, with reasons, in the plan. `es.sqlite3` ships
   **zero** Spanish inflections.
4. **Homographs are kept.** `me` → "me" is a correct translation.
5. **`pasito` → "nativity scene" is wrong** (it is "little step") and is
   **deliberately not fixed**: 437 pack entries have a diminutive-shaped
   lemma with a known base and nearly all are false positives (`albita` is
   not a small `albo`). 437 corrupted entries to fix 1 card of 147 is a bad
   trade. 8 of the song's 9 diminutives are already correct.
6. **`share_plus` drops `fileNameOverrides`** on this path — the channel
   receives only `paths` and `mimeTypes`. Don't re-add it; the mime type is
   what routes the file to AnkiDroid.

## Standing rules that bit, hard

- **Never open a GUI on the user's monitors.** Use `scripts/run_headless.sh`
  (Xvfb + xdotool).
- **Wrap builds in `scripts/capped_run.sh`** (or use `phone_deploy.sh`).
- **Check for a live Steam game before launching anything GPU-bound.**
- **250-line cap applies to tests and prose too.** Adding one line to
  `testsAndMisc/phone_focus_mode/config.sh` pushed it to 251 and blocked the
  commit.
- **Branch coverage, `fail_under = 100`, no suppressions.**
- **Real `dart:io` deadlocks `testWidgets`** — use `tester.runAsync` or keep
  setup synchronous. `test/screens/flow_harness.dart` wraps it.
- **`pumpAndSettle` never returns while an indeterminate progress bar
  animates.**
- **Driving the phone by tap is error-prone**: screenshots are downscaled 2x,
  so double the coordinates, and a stray tap silently unticked a card and
  turned 147 into 146. Verify the count on screen before exporting.
- **`phone_deploy.sh` can exit 0 while the build failed** — the task
  notification said success and the APK was 20 minutes stale. Read the log
  tail for `exit 34`, or check the APK's mtime.
- **Verify before claiming.** Three agreed acceptance numbers (≥150, 143, 148)
  were each wrong on measurement, and the previous session's confident DNS
  diagnosis was a missing manifest line.

## Open, non-blocking

- `testsAndMisc` commit `1d7271f0` bundles this repo's glyph work under
  another workstream's message and **was pushed**. Kuhy's call; leaving it.
- AnkiDroid's `MANAGE_EXTERNAL_STORAGE` grant is still in place (see above).
