#!/usr/bin/env bash
# Headless launch smoke test for the Flutter Linux bundle under Xvfb.
# Fails if the app exits within the first $WARMUP seconds (a crash would show
# up as an exit), otherwise reports PASS. Not a real playback test.
#
# CI must install xvfb and a libmpv.so.2 provider (Debian/Ubuntu: libmpv2).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_bundle

WARMUP="${WARMUP_SECONDS:-10}"
BIN="$BUNDLE_DIR/retro_tv"
OUT="/tmp/retro-tv-smoke.log"

command -v xvfb-run >/dev/null 2>&1 || die "xvfb-run not found"
ldconfig -p 2>/dev/null | grep -q 'libmpv.so.2' || die "libmpv.so.2 not on the host; install libmpv2 (Debian/Ubuntu) or mpv-libs (Fedora)"

xvfb-run -a --server-args="-screen 0 1280x800x24" bash -c "
    '$BIN' > '$OUT' 2>&1 &
    PID=\$!
    sleep $WARMUP
    if ! kill -0 \$PID 2>/dev/null; then
        wait \$PID || true
        echo 'SMOKE FAIL: app exited during warmup'; tail -n 40 '$OUT'
        exit 1
    fi
    kill \$PID 2>/dev/null || true
    wait \$PID 2>/dev/null || true
    echo 'SMOKE PASS: process stayed alive for ${WARMUP}s'
"

grep -q 'flutter: .*SEVERE' "$OUT" && { echo "SMOKE FAIL: Flutter SEVERE error in log"; exit 1; } || true

exit 0