#!/bin/bash

# ============================================================================
# Install lyricanki on the phone, push the dictionary pack, and print the
# checks that settle the done condition.
#
# NEVER uninstalls and NEVER clears app data: `adb install -r` only. Wiping
# would destroy a real Anki collection on a device that has one.
# ============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly DEVICE="23181JEGR08034"
readonly PACKAGE="com.kuhy.lyricanki"
readonly LANGUAGE="es"

PACK_PATH="$REPO_ROOT/tools/pack_builder/lyricanki-$LANGUAGE.sqlite"
SKIP_BUILD=0

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  --pack PATH    Dictionary pack to push (default: built pack)"
    echo "  --skip-build   Install the existing APK without rebuilding"
    echo "  -h, --help     Show this help"
    exit 0
}

validate_requirements() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "Error: adb not found. Install android-tools." >&2
        exit 1
    fi
    if ! adb devices | grep -q "^${DEVICE}[[:space:]]*device$"; then
        echo "Error: phone $DEVICE is not connected." >&2
        echo "Plug it in, unlock it, and confirm the USB debugging prompt." >&2
        exit 1
    fi
    if [[ ! -f "$PACK_PATH" ]]; then
        echo "Error: dictionary pack not found at $PACK_PATH" >&2
        echo "Build it: see tools/pack_builder/README.md" >&2
        exit 1
    fi
}

build_and_install() {
    if [[ "$SKIP_BUILD" -eq 0 ]]; then
        echo "==> Building release APK"
        # Memory-capped: an unbounded build can freeze the whole desktop,
        # which costs more than the build does.
        (cd "$REPO_ROOT" &&
            "$REPO_ROOT/scripts/capped_run.sh" flutter build apk --release)
    fi
    local apk="$REPO_ROOT/build/app/outputs/flutter-apk/app-release.apk"
    [[ -f "$apk" ]] || apk="$REPO_ROOT/build/app/outputs/flutter-apk/app-debug.apk"

    echo "==> Installing (upgrade in place, data preserved)"
    adb -s "$DEVICE" install -r "$apk"
}

push_pack() {
    # Launch once so the app's data directory exists before writing into it.
    adb -s "$DEVICE" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    sleep 3

    local target="/sdcard/Android/data/$PACKAGE/files/packs"
    echo "==> Pushing pack ($(du -h "$PACK_PATH" | cut -f1)) to $target"
    adb -s "$DEVICE" shell mkdir -p "$target"
    adb -s "$DEVICE" push "$PACK_PATH" "$target/lyricanki-$LANGUAGE.sqlite"
}

print_checks() {
    cat <<'CHECKS'

============================================================================
On the phone, verify the done condition:
============================================================================
  1. Open lyricanki. The dictionary should report as installed.
  2. Search "Despacito" and select track #36856755 (Luis Fonsi, 4:33).
     NOT #36844210 -- that is the Bieber remix, which has English verses.
  3. Confirm the review screen lists 147 words, then export.
  4. Import the .apkg into AnkiDroid. Expect exactly 147 notes, each with
     word / POS / gloss / lyric line, and zero empty glosses.
  5. Re-generate, re-import, and confirm the count is STILL 147 with no
     duplicates -- that is the half of the condition guids and csum exist for.
============================================================================
CHECKS
}

main() {
    validate_requirements
    build_and_install
    push_pack
    print_checks
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --pack)
            PACK_PATH="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

main "$@"
