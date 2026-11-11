#!/bin/bash

# ============================================================================
# Deploy lyricanki to kuhy's Pixel for real: release build + install via
# phone_deploy.sh, push the dictionary pack, then a health check. Exits
# non-zero unless every check passes.
#
# Idempotent: install is `adb install -r` (upgrade in place) and the pack is
# pushed only when the phone's copy differs in size. NEVER uninstalls and
# NEVER clears app data -- that would destroy the user's settings and pack.
#
# Builds from this checkout (the code being shipped). The release key and the
# gitignored pack are not in a fresh worktree, so both fall back to the live
# checkout ~/src/lyricanki, which is only read, never pulled or written: the
# app runs on the phone, not from that tree.
#
# Env overrides (tests): DEPLOY_REPO_ROOT, DEPLOY_SERIAL, LYRICANKI_PACK, PHONE_DEPLOY,
# LIVE_CHECKOUT, HEALTH_SETTLE_SECS.
# ============================================================================

set -euo pipefail

REPO_ROOT="${DEPLOY_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
readonly REPO_ROOT
readonly SERIAL="${DEPLOY_SERIAL:-23181JEGR08034}"
readonly PACKAGE="com.kuhy.lyricanki"
readonly PACK_NAME="lyricanki-es.sqlite"
readonly PACK_DIR="/sdcard/Android/data/$PACKAGE/files/packs"
readonly PHONE_DEPLOY="${PHONE_DEPLOY:-$HOME/.claude/scripts/phone_deploy.sh}"
readonly LIVE_CHECKOUT="${LIVE_CHECKOUT:-$HOME/src/lyricanki}"
readonly SETTLE_SECS="${HEALTH_SETTLE_SECS:-5}"

die() {
    echo "deploy: FAIL: $*" >&2
    exit 1
}

phone() { adb -s "$SERIAL" "$@"; }

# First existing pack: explicit override, this checkout, live checkout.
resolve_pack() {
    local candidate
    for candidate in "${LYRICANKI_PACK:-}" \
        "$REPO_ROOT/tools/pack_builder/$PACK_NAME" \
        "$LIVE_CHECKOUT/tools/pack_builder/$PACK_NAME"; do
        if [[ -n "$candidate" && -s "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# A fresh worktree has no key.properties (gitignored); without it the build
# would be refused by phone_deploy. Copy the live checkout's, mode 600.
ensure_release_key() {
    local props="$REPO_ROOT/android/key.properties"
    [[ -f "$props" ]] && return 0
    [[ -f "$LIVE_CHECKOUT/android/key.properties" ]] \
        || die "no android/key.properties here or in $LIVE_CHECKOUT"
    install -m 600 "$LIVE_CHECKOUT/android/key.properties" "$props"
}

last_update() {
    phone shell dumpsys package "$PACKAGE" | tr -d '\r' \
        | sed -n 's/^[[:space:]]*lastUpdateTime=//p' | head -1
}

push_pack() {
    local pack="$1" local_size phone_size
    local_size="$(stat -c %s "$pack")"
    phone_size="$(phone shell stat -c %s "$PACK_DIR/$PACK_NAME" 2>/dev/null | tr -d '\r' || true)"
    if [[ "$phone_size" == "$local_size" ]]; then
        echo "==> Pack already on phone ($local_size bytes)"
        return 0
    fi
    echo "==> Pushing pack ($local_size bytes)"
    phone shell mkdir -p "$PACK_DIR"
    phone push "$pack" "$PACK_DIR/$PACK_NAME" >/dev/null
}

health_check() {
    local pack="$1" before="$2" after phone_size
    after="$(last_update)"
    [[ -n "$after" ]] || die "$PACKAGE is not installed"
    [[ "$after" != "$before" ]] || die "install did not update $PACKAGE (lastUpdateTime unchanged)"

    phone_size="$(phone shell stat -c %s "$PACK_DIR/$PACK_NAME" 2>/dev/null | tr -d '\r' || true)"
    [[ "$phone_size" == "$(stat -c %s "$pack")" ]] || die "pack missing or wrong size on phone"

    # Fresh launch, then look for a crash from this package since the clear.
    phone logcat -c
    phone shell am start -n "$PACKAGE/.MainActivity" >/dev/null
    sleep "$SETTLE_SECS"
    [[ -n "$(phone shell pidof "$PACKAGE" | tr -d '\r')" ]] || die "$PACKAGE not running after launch"
    if phone logcat -d -b crash -b main | grep -A1 'FATAL EXCEPTION' | grep -q "Process: $PACKAGE"; then
        die "$PACKAGE crashed on launch (see adb logcat -b crash)"
    fi
    echo "==> Health OK: installed (lastUpdateTime=$after), pack present, app running"
}

main() {
    local pack before
    pack="$(resolve_pack)" || die "pack $PACK_NAME not found (see tools/pack_builder/README.md)"
    command -v adb >/dev/null 2>&1 || die "adb not found"
    adb devices | grep -q "^${SERIAL}[[:space:]]*device$" || die "phone $SERIAL not connected"
    ensure_release_key

    before="$(last_update)"
    echo "==> Release build + install via phone_deploy.sh"
    ADB_SERIAL="$SERIAL" bash "$PHONE_DEPLOY" "$REPO_ROOT" --release \
        || die "phone_deploy.sh failed (exit $?)"
    push_pack "$pack"
    health_check "$pack" "$before"
}

main "$@"
