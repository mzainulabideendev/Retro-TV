#!/usr/bin/env bash
# Full APT end-to-end install test (must run as root).
#
# Validates the produced repository exactly like a user would:
#   1. install public keyring
#   2. add repository (signed-by)
#   3. apt update
#   4. apt-cache policy (locate package)
#   5. download package
#   6. install package (resolves dependencies from the archive)
#   7. verify executable + desktop entry exist
#   8. remove package
#
# Usage: test-apt-install.sh <apt-repo-dir> <expected-version> [<expected-version-code>]
# Example: test-apt-install.sh build/repository/apt 1.2.1 5
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "test-apt-install: must run as root" >&2; exit 1; }

APT_DIR="${1:?usage: test-apt-install.sh <apt-repo-dir> <vname> <vcode>}"
VNAME="${2:?expected version name missing}"
VCODE="${3:?expected version code missing}"
EXPECTED="$VNAME-$VCODE"

KEYRING=/etc/apt/keyrings/retro-tv-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/retro-tv-test.list
mkdir -p /etc/apt/keyrings

cp "$APT_DIR/retro-tv-archive-keyring.gpg" "$KEYRING"
echo "deb [signed-by=$KEYRING] file:$APT_DIR stable main" > "$LIST"

cleanup() { rm -f "$LIST"; }
trap cleanup EXIT

echo "[1/8] apt-get update"
# The CI container uses a pinned Debian snapshot whose signed Release metadata
# has an expired Valid-Until. Disable only that freshness check for this update;
# APT still verifies the repository signatures as usual.
apt-get -o Acquire::Check-Valid-Until=false update -qq \
    || { echo "test-apt-install: apt update FAILED" >&2; exit 1; }

echo "[2/8] locate package (apt-cache policy)"
apt-cache policy retro-tv
CANDIDATE="$(apt-cache policy retro-tv | awk '/Candidate:/{print $2; exit}')"
[ "$CANDIDATE" = "$EXPECTED" ] || { echo "test-apt-install: expected candidate $EXPECTED but got $CANDIDATE" >&2; exit 1; }

echo "[3/8] download package"
DL="$(mktemp -d)"
( cd "$DL" && apt-get download retro-tv ) || { echo "test-apt-install: apt-get download FAILED" >&2; exit 1; }

echo "[4/8] install package"
apt-get install -y --no-install-recommends retro-tv || { echo "test-apt-install: apt-get install FAILED" >&2; exit 1; }

echo "[5/8] verify metadata"
dpkg -s retro-tv | grep -q "^Version: $EXPECTED$" \
    || { echo "test-apt-install: installed version mismatch" >&2; exit 1; }

echo "[6/8] verify executable + desktop entry"
test -x /usr/bin/retro_tv || { echo "test-apt-install: /usr/bin/retro_tv missing" >&2; exit 1; }
test -x /usr/lib/retro-tv/retro_tv || { echo "test-apt-install: /usr/lib/retro-tv/retro_tv missing" >&2; exit 1; }
test -f /usr/share/applications/com.retrotv.retro_tv.desktop \
    || { echo "test-apt-install: desktop entry missing" >&2; exit 1; }
file /usr/bin/retro_tv

echo "[7/8] remove package"
apt-get remove -y retro-tv || { echo "test-apt-install: remove FAILED" >&2; exit 1; }

echo "[8/8] cleanup download dir"
rm -rf "$DL"

echo "test-apt-install: PASS (installed retro-tv $EXPECTED and removed it)"