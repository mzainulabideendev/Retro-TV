#!/usr/bin/env bash
# Build the Snap (best-effort, see snap/snapcraft.yaml notes).
# Requires snapcraft + snapd and a Snap Store login for publishing.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

command -v snapcraft >/dev/null 2>&1 || die "snapcraft not found"
snapcraft --version >/dev/null 2>&1

OUT="$PACKAGES_DIR"
mkdir -p "$OUT"
snapcraft pack "$ROOT_DIR/snap" --output "$OUT/retro-tv_${VERSION_LINE:-latest}_amd64.snap"
log "snap written to $OUT"