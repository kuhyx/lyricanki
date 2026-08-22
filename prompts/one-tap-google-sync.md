> **This file is a ready-to-use prompt.** Open `~/lyricanki` and say
> "do one-tap-google-sync". It is self-contained.
>
> Written 2026-08-22 from a user report, immediately after the
> exported-song-history work shipped. Every claim below was checked against
> the tree that day; **re-verify before trusting it**, since the repo moves.

## ⛔ WHEN YOU FINISH

Delete this file and commit the deletion with the work:

```bash
git rm prompts/one-tap-google-sync.md
```

A finished prompt is indistinguishable from a pending one, and the next
session will re-run it.

## The report

> "firebase sync is not good enough — look at how other apps do it, providing
> email and password is a FALLBACK OPTIONAL option, what should really be
> implemented is a ONE TAP FIREBASE connect, look at how example 'todo' app
> that just has tap verification to firebase — THIS is how it should work and
> how all apps should work"

## What is actually wrong

`lyricanki/lib/screens/sync_screen.dart` builds `SyncSettingsScreen` with
**no `googleFirebaseFactory` and no `googleAvailable`**. That parameter is
nullable and null *hides the Google button entirely*
(`sync_settings_ui/lib/src/sync_settings_widget.dart:50`), so the only way to
connect is typing a long password on a phone keyboard. Every other app in the
fleet offers one tap.

This is not a missing library feature. `crdt_sync_flutter` **already ships**
`signInWithGoogle(SyncApp, {required tokenFetcher, ...})`
(`lib/src/bootstrap.dart`), tested and covered. What is missing is the
`tokenFetcher` — the `google_sign_in` plugin call — which cannot live in
`crdt_sync` (pure Dart, runs headless under systemd) and currently lives as a
**copy-pasted file in every app**.

## The real task: extract it, do not copy it again

Measured on 2026-08-22, `google_sign_in_backend.dart` (122 lines) against
`todo`'s copy, with package prefixes normalised:

| App | diff vs todo |
|---|---|
| `home_inventory` | **0 lines — byte-identical** |
| `diet_guard` | 4 lines (import paths only) |
| `wake_alarm` | 8 lines |

Plus `google_platform.dart` + `_io` + `_web` (29 lines), identical everywhere.

So: **add the Google token fetcher to `~/utils/crdt_sync_flutter`**, then have
lyricanki consume it. Do NOT paste a fifth copy into lyricanki. The whole
point of that package — written in the session before this one — is that this
glue lives in exactly one place. Copying it here would be the mistake the
package exists to prevent.

Read `~/utils/crdt_sync_flutter/README.md` first; it explains the split and
why the plugin cannot go in `crdt_sync` itself.

## The good news: no Firebase console work

The usual blocker for one-tap is registering the app's release SHA-1 in the
Firebase console. **It is already registered.** Verified 2026-08-22:

- `~/lyricanki/android/key.properties` → `storeFile=/home/kuhy/.android/release/kuhy-release.jks`
- `~/todo/android/key.properties` → **the same file**
- That keystore's SHA1 is `58:09:D4:CB:50:AE:E1:90:24:CC:06:53:FB:C0:CF:81:19:60:97:44`

`todo`'s one-tap works against that SHA-1, and lyricanki ships from the same
keystore, so the fingerprint Firebase already trusts is lyricanki's too.

Confirm before relying on it:

```bash
PW=$(grep '^storePassword=' ~/lyricanki/android/key.properties | cut -d= -f2-)
keytool -list -v -keystore /home/kuhy/.android/release/kuhy-release.jks \
  -alias kuhy -storepass "$PW" | grep SHA1
```

If that SHA-1 has changed, one-tap will fail with a `GoogleSignInException`
that looks exactly like the user cancelling — see the comment in
`todo/lib/sync/google_sign_in_backend.dart`, which calls out that exact
ambiguity.

## Constants you need (all public, all already committed elsewhere)

From `todo/lib/sync/google_sign_in_backend.dart`:

- `kSyncUid = 'OvA2REQyLIhAHOEjzwS1o877rgG3'` — already in lyricanki as
  `kSyncApp.expectedUid` (`lib/services/history_sync.dart`). Load-bearing:
  `signInWithIdp` signs in *or signs up*, so an unlinked account authenticates
  fine and is then denied every read and write.
- `kServerClientId = '845446124781-prdoherj0v64vc6egvvcp3l0693khaur.apps.googleusercontent.com'`
  — the **Web** OAuth client id. An *Android* client id here yields a token
  Firebase rejects with `audience mismatch`.

Both are public by design and ship inside every APK; the security rules, not
secrecy, protect the data. **A plain `const`, never `--dart-define`** — todo's
file documents that a dart-define was empty in every build that mattered
(phone-deploy and CI both run a bare `flutter build apk --release`), producing
a visible button that always reported "cancelled".

## Three traps, already paid for by other sessions

1. **`supportsAuthenticate()` throws `UnimplementedError`** where no
   implementation is registered — an `Error`, not an `Exception`, so it
   escapes an ordinary `catch` and takes down `build()`. That is why
   `google_platform.dart` is a conditional export gating on
   `Platform.isAndroid` rather than a question asked of the plugin.
2. **Web/desktop has no programmatic flow.** Google Identity Services signs in
   only through its own rendered button. lyricanki's desktop *is* a real Linux
   build (unlike todo's, which is the web build in Chrome), so check what
   `Platform.isAndroid` actually gives you here rather than assuming todo's
   reasoning transfers.
3. **The button must be double-gated** on `supportsGoogle && googleAvailable`.
   A visible control that can never succeed is worse than no control.

## Where the code goes

- **New, in `~/utils/crdt_sync_flutter`:** the token fetcher and its platform
  gate (`lib/src/google_sign_in.dart` + a conditional-export pair, matching
  the existing `lib/src/` layout). Add `google_sign_in: ^7.2.0` to that
  package. Export from the barrel. Bump to **v0.2.0**, tag, push — a new
  minor, never a re-cut of a pushed tag.
- **Changed:** `lyricanki/lib/screens/sync_screen.dart` — pass
  `googleFirebaseFactory` and `googleAvailable`. It is currently 38 lines, so
  there is room.
- **Changed:** `lyricanki/pubspec.yaml` — repin `crdt_sync_flutter` to the new
  tag.
- **Consider:** whether `kServerClientId` belongs beside `kSyncApp` in
  `lib/services/history_sync.dart`, or as a field on `SyncApp` itself in the
  shared package. The second is tidier and helps every future app; it is a
  breaking change to `SyncApp`, so decide deliberately and say which you chose.

## Do NOT migrate the four existing apps

`todo`, `home_inventory`, `diet_guard`, `workout_app` and `wake_alarm` keep
their own copies, pinned to `crdt_sync_dart-v0.10.0`. Migration is
forward-only and those fallbacks are load-bearing. Converging them is its own
task. (Note in passing: they are missing the `tryParse` empty-password fix
released in `crdt_sync_dart-v0.11.0`, so `todo`'s Google sign-in currently
writes an account marker it cannot read back.)

## Hard rules in this repo

- **Branch coverage `fail_under = 100`, no suppressions.** The plugin call
  itself is unreachable under `flutter test` — todo wraps exactly that region
  in `coverage:ignore-start/end` and keeps everything above it pure and
  covered. Copy that shape; `crdt_sync_flutter` is at 100% today and must stay
  there. `installFakeSecureStorage()` ships from
  `crdt_sync_flutter/lib/testing/` for the keystore half.
- **250-line cap on every file, tests and prose included.** Plan the split up
  front.
- **Real `dart:io` deadlocks `testWidgets`** — use `tester.runAsync`, or keep
  setup synchronous. `test/screens/flow_harness.dart` wraps this.
- **`pumpAndSettle` never returns** while an indeterminate progress bar
  animates — `SyncSettingsScreen` shows one while it probes the keystore, so
  pump, never settle. See `test/screens/sync_screen_test.dart`.
- **Never open a GUI on the user's monitors** — `scripts/run_headless.sh`.
- **Wrap builds in `scripts/capped_run.sh`**, or use
  `~/.claude/scripts/phone_deploy.sh <app-dir> --release`.
- **`phone_deploy.sh` can exit 0 while the build failed.** Check the APK mtime
  against `date`, and the installed `versionName` against `pubspec.yaml`.
- Theming comes entirely from `design_system`. Do not invent colours.
- Gate is `./scripts/ci_mirror.sh`. `dart format` runs with
  `--set-exit-if-changed`, so run the gate twice if the first pass reformats.

## Done when

- The Sync settings screen in lyricanki shows a **"Sign in with Google"**
  button on Android, above the email/password fields.
- Tapping it raises the OS account picker, and choosing the sync account
  leaves the screen reporting connected — **with nothing typed**.
- The email/password fields remain, below, as the fallback.
- The Google glue exists **once**, in `crdt_sync_flutter`. `grep -rn
  "GoogleSignIn.instance" ~/lyricanki/lib` returns nothing.
- `./scripts/ci_mirror.sh` green (100% coverage, no suppressions beyond the
  platform-channel region), and `crdt_sync_flutter`'s own suite still green.

## Verify

**On the phone (Pixel 6a, Android 16 / SDK 36), not only on desktop.** This is
the whole point of the change and it cannot be verified anywhere else — the
programmatic flow is Android-only.

1. `~/.claude/scripts/phone_deploy.sh ~/lyricanki --release`
2. Open Sync settings, tap **Sign in with Google**, pick the sync account.
3. Confirm it reports connected without typing.
4. Then prove sync actually works, which the previous session could not:
   export a song, tap the sync icon, and confirm it reports a merge. Best
   evidence is two devices — export different songs on the phone and on the
   desktop build, sync both, and confirm each ends up with both rows.

Report what you saw on the device. Per this repo's standing note: three agreed
acceptance numbers were each wrong on measurement, so state the observation,
not the expectation. If the account picker never appears, say so plainly
rather than reporting the build as done.
