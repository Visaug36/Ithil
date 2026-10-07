#!/bin/bash
# Takes the README screenshots from the -demo build: each scene is a fresh launch with sample data in a
# temporary folder (your own calendar is never touched), pinned to the design's "now".
#
#   scripts/screenshots/capture.sh path/to/Ithil.app docs/images
set -euo pipefail

app="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out="$2"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out" build/screenshot-logs
swiftc -O "$here/window-bounds.swift" -o build/window-bounds

debug_dump() {
    local name="$1"
    echo "::group::Debug for $name"
    build/window-bounds --list || true
    screencapture -x "build/screenshot-logs/$name-screen.png" || true
    ls -la ~/Library/Logs/DiagnosticReports 2> /dev/null | tail -n 5 || true
    cat "build/screenshot-logs/$name.log" 2> /dev/null | tail -n 40 || true
    echo "::endgroup::"
}

shot() {
    local name="$1"
    shift
    pkill -x Ithil 2> /dev/null || true
    sleep 1
    open -n -F -a "$app" --stdout "$PWD/build/screenshot-logs/$name.log" --stderr "$PWD/build/screenshot-logs/$name.log" \
        --args -demo -demoNow 2026-10-06T13:50 -demoWindowSize 1280x800 -ApplePersistenceIgnoreState YES "$@"
    local pid=""
    local bounds=""
    for _ in $(seq 1 60); do
        sleep 0.5
        pid=$(pgrep -n -x Ithil || true)
        [[ -n "$pid" ]] || continue
        bounds=$(build/window-bounds "$pid" 2> /dev/null || true)
        [[ -n "$bounds" ]] && break
    done
    if [[ -z "$bounds" ]]; then
        echo "::error::No window for $name (pid ${pid:-none})"
        debug_dump "$name"
        pkill -x Ithil 2> /dev/null || true
        return 1
    fi
    sleep 4  # let the scene settle (popovers, panels, the file counts)
    bounds=$(build/window-bounds "$pid")
    screencapture -x -R"$bounds" "$out/$name.png"
    echo "$name: $bounds"
    pkill -x Ithil 2> /dev/null || true
    sleep 1
}

shot week-night -demoAppearance night -demoSpan week
shot week-dawn -demoAppearance dawn -demoSpan week
shot month-dawn -demoAppearance dawn -demoSpan month
shot details-night -demoAppearance night -demoSpan week -demoScene details
shot quickadd-night -demoAppearance night -demoSpan week -demoScene quickAdd
