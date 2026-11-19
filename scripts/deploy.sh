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
# Builds from the live checkout ~/src/lyricanki, never from this one: the
# board runs this script in a git worktree, and phone_deploy.sh refuses a
# production build from any worktree (exit 49), so an unmerged build can never
# replace the app. The live checkout is pulled --ff-only first, and the deploy
# goes on only when its HEAD (origin's) contains this checkout's HEAD, with no
# uncommitted tracked edits: only pushed code ships, never local WIP. The
# release key and the pack are gitignored and already live there.
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

# Bring the live checkout to the commit being deployed. git's own message
# leads a failed pull: the board's deploy healer keys on it.
sync_live_checkout() {
    local want got dirty
    want="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    git -C "$LIVE_CHECKOUT" pull --ff-only --quiet \
        || die "cannot fast-forward $LIVE_CHECKOUT to origin (local commits or edits there)"
    got="$(git -C "$LIVE_CHECKOUT" rev-parse HEAD)"
    [[ -z "$(git -C "$LIVE_CHECKOUT" rev-list '@{u}..HEAD')" ]] \
        || die "$LIVE_CHECKOUT has local commits not on origin: push or drop them"
    # Origin may have moved past $want since it was pushed: its newer HEAD
    # still holds $want and is merged code, so that is what ships.
    git -C "$LIVE_CHECKOUT" merge-base --is-ancestor "$want" "$got" 2>/dev/null \
        || die "$want is not on origin (the pulled $LIVE_CHECKOUT is at $got): push first"
    echo "==> Building $got from $LIVE_CHECKOUT"
    dirty="$(git -C "$LIVE_CHECKOUT" diff --name-only HEAD)"
    [[ -z "$dirty" ]] \
        || die "uncommitted edits in $LIVE_CHECKOUT would ship: $(tr '\n' ' ' <<<"$dirty")"
    [[ -f "$LIVE_CHECKOUT/android/key.properties" ]] \
        || die "no android/key.properties in $LIVE_CHECKOUT"
}

# Captured into a variable, not piped into head/grep -q: an early-exiting
# reader SIGPIPEs the writer and pipefail turns that into a failure.
last_update() {
    local dump
    dump="$(phone shell dumpsys package "$PACKAGE" | tr -d '\r')"
    sed -n 's/^[[:space:]]*lastUpdateTime=//p' <<<"$dump" | sed -n 1p
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
    # -S force-stops first, so the pid check sees this launch, not the one
    # phone_deploy made. Both buffers are cleared so an old crash cannot fail
    # a later run.
    phone logcat -b main -b crash -c
    phone shell am start -S -n "$PACKAGE/.MainActivity" >/dev/null
    sleep "$SETTLE_SECS"
    [[ -n "$(phone shell pidof "$PACKAGE" | tr -d '\r')" ]] || die "$PACKAGE not running after launch"
    local log
    log="$(phone logcat -d -b crash -b main | tr -d '\r')"
    if [[ "$log" == *"Process: $PACKAGE,"* ]]; then
        die "$PACKAGE crashed on launch (see adb logcat -b crash)"
    fi
    echo "==> Health OK: installed (lastUpdateTime=$after), pack present, app running"
}

main() {
    local pack before
    pack="$(resolve_pack)" || die "pack $PACK_NAME not found (see tools/pack_builder/README.md)"
    command -v adb >/dev/null 2>&1 || die "adb not found"
    adb devices | grep -q "^${SERIAL}[[:space:]]*device$" || die "phone $SERIAL not connected"
    sync_live_checkout

    before="$(last_update)"
    echo "==> Release build + install via phone_deploy.sh ($LIVE_CHECKOUT)"
    ADB_SERIAL="$SERIAL" bash "$PHONE_DEPLOY" "$LIVE_CHECKOUT" --release \
        || die "phone_deploy.sh failed (exit $?)"
    push_pack "$pack"
    health_check "$pack" "$before"
}

main "$@"
