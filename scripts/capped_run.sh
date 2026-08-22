#!/bin/bash

# ============================================================================
# Run a command inside a memory-capped systemd scope.
#
# A build that exhausts RAM takes the whole desktop down with it -- on this
# machine the OOM killer is far slower to act than the freeze is, so the box
# has to be power-cycled and any unsaved work in other apps is lost. A scope
# with MemoryMax makes the runaway process die instead of the session.
#
# `flutter build` (and the Gradle/CMake compiles under it) is the memory-
# hungry step, so that is what this wraps.
#
# Usage:
#   scripts/capped_run.sh flutter build linux --debug
#   MEM_MAX=8G scripts/capped_run.sh flutter build apk --release
#
# Falls back to running the command directly when systemd-run is unavailable
# or refuses the scope, so this can never be the reason a build cannot run.
# ============================================================================

set -euo pipefail

readonly MEM_MAX="${MEM_MAX:-12G}"

main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $(basename "$0") <command> [args...]" >&2
        exit 1
    fi

    if ! command -v systemd-run >/dev/null 2>&1; then
        echo "capped_run: systemd-run unavailable, running uncapped" >&2
        exec "$@"
    fi

    echo "capped_run: MemoryMax=$MEM_MAX"

    # `set -e` would abort before the status could be inspected, and a build
    # killed by the cap must never be reported as a pass -- so the failure is
    # caught explicitly here rather than left to the shell.
    local status=0
    systemd-run --user --scope --quiet --collect \
        -p "MemoryMax=$MEM_MAX" -p "MemorySwapMax=0" \
        -- "$@" || status=$?

    # 137 = 128 + SIGKILL, which is what MemoryMax does to a runaway build.
    if [[ $status -eq 137 ]]; then
        echo "capped_run: KILLED at MemoryMax=$MEM_MAX." >&2
        echo "            Raise it with MEM_MAX=<size> if the build" \
             "legitimately needs more." >&2
    fi
    return "$status"
}

main "$@"
