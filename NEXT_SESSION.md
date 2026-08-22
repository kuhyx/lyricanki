# lyricanki — next session prompt

Paste everything below the line into a fresh Claude session with cwd `~/lyricanki`.

---

Work on `~/lyricanki`. Read `/home/kuhy/.claude/plans/learn-language-through-the-zany-boole.md`
first — it is the approved plan and records every settled decision (Q1–Q21).

## The one thing left: verify the app on Android

Everything else is built, green, pushed and released. Desktop is fully
verified end to end; the Android half is verified only as far as the network.

### If the phone is connected (preferred — it has working DNS)

```bash
adb devices          # expect 23181JEGR08034
bash scripts/phone_verify.sh
```

The script builds, `adb install -r`s and pushes the pack. It refuses to run
without the phone, and **never uninstalls, never `pm clear`s** — the app's
data is not yours to wipe.

**Expect a signature clash on the first install.** Every release APK built
before commit `cf8529b` was debug-signed (the Gradle config still had
Flutter's scaffolded TODO), so if a debug-signed lyricanki is already on the
phone, `install -r` fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. On the
emulator this was resolved by uninstalling — **do not do that on the
phone without asking.** Check first:

```bash
adb -s 23181JEGR08034 shell dumpsys package com.kuhy.lyricanki | grep -m1 signatures
```

If the app was never installed on the phone, this is moot and a plain
`install -r` works.

### If the phone is unavailable, use the emulator

An AVD named `lyricanki_test` (Android 34, google_apis, x86_64) already
exists. Boot it **headless — never open a window on the user's monitors**:

```bash
~/Android/Sdk/emulator/emulator -avd lyricanki_test -no-window -no-audio \
  -no-boot-anim -gpu swiftshader_indirect -port 5560 &
adb -s emulator-5560 wait-for-device
adb -s emulator-5560 shell getprop sys.boot_completed   # 1 when ready
```

**Known blocker — do not re-derive.** The emulator resolves DNS from the
shell (`ping lrclib.net` works) but the app's Dart resolver gets
`Failed host lookup: 'lrclib.net'`. The network is `VALIDATED` with
`DnsAddresses: [ /fec0::3, /10.0.2.3 ]` — an IPv6 forwarder listed FIRST,
which is the usual explanation for exactly this split (shell resolves over
IPv4, apps try IPv6 and fail).

Tried, all still failing: `-dns-server 8.8.8.8,1.1.1.1`; `setprop net.dns1`
and `net.dns2` as root; `settings put global private_dns_mode off`;
`sysctl -w net.ipv6.conf.{all,wlan0}.disable_ipv6=1`; app restarts between
each. Untried: `-http-proxy`, a `-wipe-data` cold boot, an older system
image, `-netdelay none -netspeed full`.

**Do not sink a session into this.** The phone has working DNS and is the
short path. Everything that does NOT need the network is already confirmed
on the emulator, so what remains genuinely requires a working resolver.

## What to check on the device

Install, side-load the pack, then walk the app:

```bash
adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk
adb -s <device> push tools/pack_builder/lyricanki-es.sqlite \
  /sdcard/Android/data/com.kuhy.lyricanki/files/packs/
```

1. Open lyricanki — the dictionary must report **installed / "Ready"**.
2. Search "Despacito", select **`#36856755`** (Luis Fonsi, 4:33) — *not*
   `#36844210`, the Bieber remix with English verses.
3. Review screen must offer **Export 147 cards**. Export.
4. Import into **AnkiDroid**: expect **exactly 147 notes**, each with
   word / POS / gloss / lyric line, **zero** empty glosses.
5. **Re-import the same file — still 147, no duplicates.**

Steps 1 and the side-load are already confirmed on the emulator. Steps 2–5
are confirmed on desktop against the real `anki` library, never on Android.

Drive the emulator with `adb shell input tap X Y` at **1080x2400** — the
screencap is downscaled 2x, so screenshot coordinates must be doubled. Tap
the field before `input text`, or the text goes nowhere.

## State: verified, not assumed

Pushed to `github.com/kuhyx/lyricanki` (public). `scripts/ci_mirror.sh` green:
analyze clean, **252 tests, 711/711 lines (100%)**, every file under 250 lines.
`tools/pack_builder`: **82 tests, 100% branch**, no suppressions.

- **Pack released** as `pack-es-v1`. The URL the app actually requests was
  checked: HTTP 200, 44,974,080 bytes.
- **Desktop, end to end**: search → track `#36856755` → "Export 147 cards" →
  `.apkg` → imported into the **real `anki` library**: 147 notes, 0 empty
  glosses, 4 fields each; re-import leaves it at 147.
- **Android, partial**: the release-signed APK (`CN=kuhy`, verified with
  apksigner) installs; `getExternalStorageDirectory()` takes the Android
  branch and creates `files/packs/`; `adb push` side-loads the 43 MB pack
  with no root and it survives a reboot; app reports "Ready".
- **CI is green end to end**: `release-apk` builds, signs, verifies the
  signature and publishes. `v1.0.15` is now the "Latest" release, which is
  exactly the case `PackStore.packTag` guards — the pinned pack URL was
  re-checked after that and still returns HTTP 200 / 44,974,080 bytes.

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

## Standing rules that bit, hard

- **Never open a GUI on the user's monitors.** Not the primary, not the
  secondary. It steals focus and interrupts their work — they said so twice.
  Use `scripts/run_headless.sh` (Xvfb + xdotool), which is how the desktop
  verification above was done with zero windows on their screens.
- **Wrap builds in `scripts/capped_run.sh`.** The desktop had to be
  power-cycled mid-session; cause unproven, but an unbounded build takes the
  whole session down before the OOM killer acts.
- **Check for a live Steam game before launching anything GPU-bound.**
- **250-line cap applies to tests and prose too.**
- **Branch coverage, `fail_under = 100`, no suppressions.**
- **Real `dart:io` deadlocks `testWidgets`** — use `tester.runAsync` or keep
  setup synchronous. `test/screens/flow_harness.dart` wraps it.
- **`pumpAndSettle` never returns while an indeterminate progress bar
  animates.**
- **Verify before claiming.** Three agreed acceptance numbers (≥150, 143,
  148) were each wrong on measurement, and the mock that returned `null`
  where the real platform *throws* hid a crash that shipped.

## Open, non-blocking

- `testsAndMisc` commit `1d7271f0` bundles this repo's glyph work under
  another workstream's message and **was pushed**. Kuhy's call; leaving it.
