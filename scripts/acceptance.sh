#!/bin/bash

# ============================================================================
# End-to-end acceptance gate for the pinned track.
#
# Unlike scripts/ci_mirror.sh this needs the REAL dictionary pack and network
# access to LRCLIB, so it is not part of the offline unit suite. Q8 forbids
# committing lyrics, so the fixture holds only their SHA-256 plus the derived
# counts; this script re-fetches, re-hashes and re-measures.
# ============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$SCRIPT_DIR")"
readonly FIXTURE="$REPO_ROOT/test/fixtures/despacito_36856755.json"
PACK="${1:-$REPO_ROOT/tools/pack_builder/lyricanki-es.sqlite}"

if [[ ! -f "$PACK" ]]; then
    echo "Error: pack not found at $PACK" >&2
    echo "Build it first -- see tools/pack_builder/README.md" >&2
    exit 1
fi

echo "==> acceptance (real pack, live LRCLIB)"
dart run "$REPO_ROOT/tools/acceptance/acceptance.dart" "$PACK" "$FIXTURE"
