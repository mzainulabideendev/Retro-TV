#!/usr/bin/env bash
# Best-effort headless smoke test for the Flatpak build under Xvfb.
# Launching a GUI app in CI is fragile, so CI marks this continue-on-error;
# a PASS here is evidence the runtime wiring works, a FAIL is not treated as
# release-blocking.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FBBUNDLE="${1:?usage: flatpak-smoke-test.sh <.flatpak>}"
WARMUP="${WARMUP_SECONDS:-10}"

command -v xvfb-run >/dev/null 2>&1 || die "xvfb-run not found"
command -v flatpak >/dev/null 2>&1 || die "flatpak not found"
[ -f "$FBBUNDLE" ] || die "bundle not found: $FBBUNDLE"

flatpak install --user --noninteractive "$FBBUNDLE" >/dev/null 2>&1

LOG="$BUILD_DIR/flatpak-smoke.log"
xvfb-run -a --server-args="-screen 0 1280x800x24" bash -c "
    flatpak run com.retrotv.retro_tv > '$LOG' 2>&1 &
    PID=\$!
    sleep $WARMUP
    if ! kill -0 \$PID 2>/dev/null; then
        wait \$PID || true
        echo 'FLATPAK SMOKE FAIL: app exited during warmup'; tail -n 40 '$LOG'
        exit 1
    fi
    kill \$PID 2>/dev/null || true
    wait \$PID 2>/dev/null || true
    echo 'FLATPAK SMOKE PASS: process stayed alive for ${WARMUP}s'
"

exit 0