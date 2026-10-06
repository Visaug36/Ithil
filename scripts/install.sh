#!/bin/bash
# Builds a universal Release of Ithil from this checkout and installs it in /Applications.
#
#   scripts/install.sh            build and install
#   scripts/install.sh --open     …and open it afterwards
#
# The build is ad-hoc signed ("Sign to Run Locally"), which is all a Mac needs for an app you built yourself.
# Your calendar lives in the folder you chose in Ithil, so reinstalling never touches your events or files.
set -euo pipefail

cd "$(dirname "$0")/.."

open_after=false
if [[ "${1:-}" == "--open" ]]; then
    open_after=true
fi

if ! command -v xcodebuild > /dev/null; then
    echo "xcodebuild not found. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

derived_data="build/InstallDerivedData"
echo "Building Ithil (Release, Apple Silicon + Intel)…"
xcodebuild build \
    -project Ithil.xcodeproj -scheme Ithil -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    ONLY_ACTIVE_ARCH=NO \
    -quiet

app="$derived_data/Build/Products/Release/Ithil.app"
if [[ ! -d "$app" ]]; then
    echo "The build finished but $app is missing." >&2
    exit 1
fi

if pgrep -x Ithil > /dev/null; then
    echo "Quitting the running Ithil…"
    osascript -e 'tell application id "io.github.visaug36.Ithil" to quit' || true
    for _ in $(seq 1 50); do
        pgrep -x Ithil > /dev/null || break
        sleep 0.1
    done
fi

destination="/Applications/Ithil.app"
if [[ -d "$destination" ]]; then
    echo "Replacing $destination (the old copy goes to the Trash)…"
    osascript -e "tell application \"Finder\" to delete POSIX file \"$destination\"" > /dev/null
fi
ditto "$app" "$destination"
echo "Installed $destination"

if $open_after; then
    open "$destination"
fi
