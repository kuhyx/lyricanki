# lyricanki — next session prompt

Paste everything below the line into a fresh Claude session with cwd `~/lyricanki`.

---

Work on `~/lyricanki`. Read `/home/kuhy/.claude/plans/learn-language-through-the-zany-boole.md`
first — it is the approved plan and records every settled decision (Q1–Q21).

## Read this before you plan anything

**Another session (`utils-6c`) was implementing the exported-song-history
feature** described in `prompts/exported-song-history.md`. It touches
`lib/services/`, `lib/models/`, `lib/screens/song_search_screen.dart` and
`pubspec.yaml`. **Run `git log --oneline -10` and `git status` first** — if
that work has landed, the file descriptions below may be stale; if it has
not, do not start it without checking whether that session is still active.

## State: verified end to end, on both platforms

Both halves are done as of 2026-08-22 (HEAD at handoff: `55b7dcb`).

- **Android** (Pixel 6a, Android 16 / SDK 36), walked on the real phone:
  install → pack → search → track `#36856755` → **Export 147 cards** →
  export → **import into AnkiDroid** → re-import.
- **Desktop**: search and "Export 147 cards" confirmed headlessly; the
  `.apkg` verified against the real `anki` library (147 notes; a re-import
  leaves it at 147).
- CI green: analyze clean, **263 tests, 731/731 lines (100%)**, every file
  under 250 lines. `tools/pack_builder`: 82 tests, 100% branch.
- Pack released as `pack-es-v1`; the pinned URL returns HTTP 200 /
  44,974,080 bytes. Published APK is `v1.0.20`.

The AnkiDroid re-import reported *"147 notes found, 1 new, 146 used to update
existing"* against a collection that already held the notes, and left one
deck. That is the dedup guarantee, measured on-device rather than argued.

## What is actually left

Nothing is blocking. In rough order of value:

1. **Only one song has ever been exercised.** Every acceptance number comes
   from Despacito `#36856755`. A second and third song — ideally one with
   heavy enclitics (`dámelo`), one with reflexives — would show whether 147
   was luck. The `unresolved` list on the review screen is the built-in
   canary: a real Spanish word appearing there means the pack regressed.
2. **Only Spanish exists.** The pack format is language-agnostic and
   `build_pack.py` takes `--language`, but no second pack has been built.
3. **Song history** — see the coordination note at the top.

## Two bugs were found and fixed on 2026-08-22 — do not reintroduce them

1. **INTERNET permission.** Flutter's scaffold declares it only in
   `android/app/src/{debug,profile}/AndroidManifest.xml`. It is now in
   `main/` as well. Without it every release build fails with
   `Failed host lookup: 'lrclib.net'`, which reads exactly like broken DNS —
   a previous session lost itself chasing emulator DNS settings over this,
   and wrote the wrong diagnosis into the handoff as settled fact. The tell:
   `adb shell ping <host>` succeeds while the app fails. Confirm the built
   artifact, not the manifest source:
   `aapt2 dump permissions <apk> | grep uses-permission`.

2. **Export location.** `getApplicationDocumentsDirectory()` is
   `/data/user/0/<pkg>/app_flutter` on Android: app-private, invisible to
   AnkiDroid, unreadable by `adb pull` without root. The export succeeded and
   was then unreachable by the only app it exists to feed. Exports now go to
   `files/exports` in external app storage via
   `lib/services/export_destination.dart`, and are handed to a share sheet
   (`lib/services/apkg_share.dart`) because from API 30 the storage picker
   cannot browse into `Android/data` — naming a path the user cannot navigate
   to is not a fix. **If you add anything that records or reopens an export,
   get the path from `ExportDestination`; do not rebuild one.**

   **The share call is Android-only, deliberately.** share_plus's Linux
   backend is a `mailto:` url_launcher shim that throws
   `UnimplementedError: Sharing files not supported on Linux` for any share
   carrying files — verified by calling the real plugin. Calling it
   unconditionally trades an Android bug for a desktop crash, and **100%
   coverage does not catch it**, because the tests mock the channel.

## Environment traps that cost real time

- **A new `com.kuhy.*` app installs `hidden=true`** until it is in the Focus
  Owner allowlist: absent from the launcher and from `pm list packages`, with
  `am start` reporting the activity does not exist even though `dumpsys`
  lists its MAIN/LAUNCHER filter. Nothing about the app is wrong. Fixed for
  lyricanki in `testsAndMisc` `98ca3ac5`. Diagnose with
  `adb shell dumpsys package <pkg> | grep -o 'hidden=[a-z]*'` and compare
  against a known-good app.
- **`~/testsAndMisc/phone_focus_mode/deploy.sh` is for the old rooted phone**
  and dies with "Could not get root shell". The Pixel is unrooted under
  Device Owner; the policy ships as a bundled asset, so a whitelist change
  means editing `config.sh`, regenerating `policy.json` with
  `python3 -m python_pkg.focus_policy ... --redact-home`, then rebuilding and
  reinstalling focus_owner.
- **focus_owner is the Device Owner**, and DO cannot be re-provisioned on an
  unrooted Pixel without a factory reset. If the installer ever wants to
  uninstall, stop. Compare `keytool -list` against
  `apksigner verify --print-certs`, pull the live APK as a rollback first,
  and deploy via `~/.claude/scripts/phone_deploy.sh`, which does that signer
  check itself.
- **AnkiDroid holds a collection this session created**: one "Despacito"
  deck, 147 notes. It had never been opened before. If AnkiWeb sync is ever
  set up, delete that deck first or choose "download" — picking "upload"
  would push test data over the account. `MANAGE_EXTERNAL_STORAGE` was
  granted with appops; revert with
  `adb shell appops set com.ichi2.anki MANAGE_EXTERNAL_STORAGE default`.

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
  (Xvfb + xdotool). `xdotool search --name lyricanki` returns three windows
  and only the 430x1180 one accepts clicks; if `getmouselocation` reports
  `window:0` the pointer is over nothing and your clicks go nowhere.
- **Wrap builds in `scripts/capped_run.sh`**, or use `phone_deploy.sh`.
- **Check for a live Steam game before launching anything GPU-bound.**
- **250-line cap applies to tests and prose too.** Adding one line to
  `testsAndMisc/phone_focus_mode/config.sh` pushed it to 251 and blocked a
  commit; that repo also demands an evidence artifact under
  `docs/superpowers/evidence/`.
- **Branch coverage, `fail_under = 100`, no suppressions.** Run
  `./scripts/ci_mirror.sh`; `dart format` is checked with
  `--set-exit-if-changed`, so a pass that reformats something means running
  it twice.
- **Real `dart:io` deadlocks `testWidgets`** — use `tester.runAsync` or keep
  setup synchronous. `test/screens/flow_harness.dart` wraps it.
- **`pumpAndSettle` never returns while an indeterminate progress bar
  animates.**
- **Driving the phone by tap is error-prone**: screenshots are downscaled 2x,
  so double the coordinates, and a stray tap silently unticked a card and
  turned 147 into 146. Read the count on screen before exporting.
- **`phone_deploy.sh` can exit 0 while the build failed.** A task
  notification claimed success while the APK was 20 minutes stale. Check the
  log tail for `exit 34`, or the APK's mtime.
- **Verify before claiming.** Three agreed acceptance numbers (>=150, 143, 148)
  were each wrong on measurement, and a confident DNS diagnosis turned out to
  be a missing manifest line.

## Open, non-blocking

- `testsAndMisc` commit `1d7271f0` bundles this repo's glyph work under
  another workstream's message and **was pushed**. Kuhy's call; leaving it.
