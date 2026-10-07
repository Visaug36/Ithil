#!/bin/bash
# Takes the README screenshots from the -demo build: each scene is a fresh launch with sample data in a
# temporary folder (your own calendar is never touched), pinned to the design's "now".
#
#   scripts/screenshots/capture.sh path/to/Ithil.app docs/images
set -euo pipefail

app="$1"
out="$2"
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out" build
swiftc -O "$here/window-bounds.swift" -o build/window-bounds

shot() {
    local name="$1"
    shift
    "$app/Contents/MacOS/Ithil" -demo -demoNow 2026-10-06T13:50 -demoWindowSize 1280x800 \
        -ApplePersistenceIgnoreState YES "$@" > /dev/null 2>&1 &
    local pid=$!
    local bounds=""
    for _ in $(seq 1 40); do
        sleep 0.5
        bounds=$(build/window-bounds "$pid" 2> /dev/null || true)
        [[ -n "$bounds" ]] && break
    done
    if [[ -z "$bounds" ]]; then
        echo "::error::No window for $name"
        kill "$pid" 2> /dev/null || true
        return 1
    fi
    sleep 4  # let the scene settle (popovers, panels, the file counts)
    bounds=$(build/window-bounds "$pid")
    screencapture -x -R"$bounds" "$out/$name.png"
    echo "$name: $bounds"
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
    sleep 1
}

shot week-night -demoAppearance night -demoSpan week
shot week-dawn -demoAppearance dawn -demoSpan week
shot month-dawn -demoAppearance dawn -demoSpan month
shot details-night -demoAppearance night -demoSpan week -demoScene details
shot quickadd-night -demoAppearance night -demoSpan week -demoScene quickAdd
