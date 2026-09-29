#!/usr/bin/env bash
# Common helpers for the Retro TV Linux build scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PACKAGES_DIR="$BUILD_DIR/packages"
REPOSITORY_DIR="$BUILD_DIR/repository"
BUNDLE_DIR="$BUILD_DIR/linux/x64/release/bundle"

log()  { printf '[build] %s\n' "$*"; }
die()  { printf '[build] ERROR: %s\n' "$*" >&2; exit 1; }

# Read name (1.2.1) and code (5) from pubspec.yaml's `version: 1.2.1+5` line.
read_version() {
    local line version_line
    version_line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?[[:space:]]*$' "$ROOT_DIR/pubspec.yaml" | head -n1)"
    [ -n "$version_line" ] || die "could not parse version from pubspec.yaml"
    VERSION_LINE="$(echo "$version_line" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]*$//')"
    VERSION_NAME="${VERSION_LINE%%+*}"
    if [[ "$VERSION_LINE" == *"+"* ]]; then
        VERSION_CODE="${VERSION_LINE##*+}"
    else
        VERSION_CODE="0"
    fi
    log "version: name=$VERSION_NAME code=$VERSION_CODE"
}

require_bundle() {
    [ -x "$BUNDLE_DIR/retro_tv" ] || die "Flutter Linux bundle not found at $BUNDLE_DIR. Run scripts/build-linux.sh first."
}