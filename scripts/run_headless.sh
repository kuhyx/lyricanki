#!/bin/bash

# ============================================================================
# Run the Linux desktop build on a private, invisible X display.
#
# NEVER open the app on the user's monitors. A window on the primary screen
# steals focus and interrupts whatever they are doing, and even placing it on
# a secondary output is disruptive; i3 also follows mouse focus, so any
# on-screen placement is fragile. Xvfb sidesteps all of it -- the app gets a
# real X server with real rendering, on a display nothing else can see.
#
# It also removes the GPU from the picture (software rendering), which is
# worth having: the desktop froze once with a game live while a GL window
# was being launched.
#
# Usage:
#   scripts/run_headless.sh            # start, print the display
#   scripts/run_headless.sh --shot OUT # start (if needed) and screenshot
#   scripts/run_headless.sh --stop
#
# Drive it with xdotool against the same DISPLAY, e.g.
#   DISPLAY=:77 xdotool mousemove 215 1148 click 1
# ============================================================================

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BINARY="$REPO_ROOT/build/linux/x64/debug/bundle/lyricanki"
readonly DISPLAY_NUM="${DISPLAY_NUM:-:77}"
# Phone-shaped, so the layout matches the primary target platform.
readonly GEOMETRY="${GEOMETRY:-430x1180x24}"
readonly LOG="${LOG:-/tmp/lyricanki-headless.log}"

stop_all() {
    # -x: match the binary name exactly. A `pkill -f lyricanki` would also
    # match the shell running this script and kill it mid-cleanup.
    pkill -x lyricanki 2>/dev/null || true
    pkill -f "Xvfb $DISPLAY_NUM" 2>/dev/null || true
}

start_display() {
    if DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1; then
        return 0
    fi
    Xvfb "$DISPLAY_NUM" -screen 0 "$GEOMETRY" >/dev/null 2>&1 &
    local waited=0
    until DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1; do
        sleep 0.3
        waited=$((waited + 1))
        if [[ $waited -gt 40 ]]; then
            echo "Error: Xvfb did not come up on $DISPLAY_NUM" >&2
            exit 1
        fi
    done
}

start_app() {
    if pgrep -x lyricanki >/dev/null 2>&1; then
        return 0
    fi
    if [[ ! -x "$BINARY" ]]; then
        echo "==> Building (memory-capped)"
        "$REPO_ROOT/scripts/capped_run.sh" flutter build linux --debug
    fi
    DISPLAY="$DISPLAY_NUM" setsid nohup "$BINARY" > "$LOG" 2>&1 < /dev/null &

    local waited=0
    local id=""
    until [[ -n "$id" ]]; do
        sleep 0.5
        id="$(DISPLAY="$DISPLAY_NUM" xdotool search --name '^lyricanki$' 2>/dev/null | tail -1 || true)"
        waited=$((waited + 1))
        if [[ $waited -gt 60 ]]; then
            echo "Error: window never appeared; see $LOG" >&2
            exit 1
        fi
    done

    # There is no window manager on this display, so the window keeps its
    # default size unless it is told to fill the screen.
    local width="${GEOMETRY%%x*}"
    local rest="${GEOMETRY#*x}"
    local height="${rest%%x*}"
    DISPLAY="$DISPLAY_NUM" xdotool windowsize "$id" "$width" "$height"
    DISPLAY="$DISPLAY_NUM" xdotool windowmove "$id" 0 0
    sleep 2
}

main() {
    case "${1:-}" in
        --stop)
            stop_all
            echo "Stopped."
            ;;
        --shot)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $(basename "$0") --shot <output.png>" >&2
                exit 1
            fi
            start_display
            start_app
            DISPLAY="$DISPLAY_NUM" import -window root "$2"
            echo "Wrote $2"
            ;;
        "")
            start_display
            start_app
            echo "Running on $DISPLAY_NUM (invisible). Log: $LOG"
            echo "Drive it with: DISPLAY=$DISPLAY_NUM xdotool ..."
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
}

main "$@"
