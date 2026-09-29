#!/usr/bin/env bash
# Build the Flutter Linux release bundle (retro_tv) for amd64.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

command -v flutter >/dev/null 2>&1 || die "flutter not found on PATH (use FLUTTER_VERSION 3.47.2, channel stable)"
read_version

cd "$ROOT_DIR"
flutter pub get
flutter build linux --release

[ -x "$BUNDLE_DIR/retro_tv" ] || die "expected bundle at $BUNDLE_DIR"
log "bundle ready: $BUNDLE_DIR"
du -sh "$BUNDLE_DIR"