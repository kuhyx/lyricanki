#!/bin/bash

# ============================================================================
# CI mirror: reproduce what CI runs, locally, before push.
#
# Flutter analogue of diet-guard's/screen-locker's Python ci_mirror.sh (clean
# environment -> full check -> fail closed). There is no venv to isolate here
# -- `flutter clean` clears build/ and cached build artifacts so a stale
# incremental build can't hide a real failure, which is the equivalent
# guarantee.
# ============================================================================

set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

main() {
    cd "$REPO_DIR"

    echo "==> flutter clean"
    flutter clean

    echo "==> flutter pub get"
    flutter pub get

    echo "==> flutter analyze"
    flutter analyze

    echo "==> dart format --set-exit-if-changed"
    dart format --set-exit-if-changed lib/ test/

    echo "==> flutter test --coverage"
    flutter test --coverage

    # Q11: 100% coverage is a gate here, not a convention. lyricanki is the
    # first app repo to enforce it -- see the plan's Coverage note.
    echo "==> coverage gate (100%)"
    "$REPO_DIR/scripts/check_coverage.sh" coverage/lcov.info 100

    echo "CI mirror passed."
}

main "$@"
