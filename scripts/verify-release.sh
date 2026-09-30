#!/usr/bin/env bash
# Verify every artifact produced for a release:
#   - files present (deb, rpm, flatpak, SHA256SUMS, repo metadata)
#   - checksums match actual artifacts
#   - APT InRelease/Release.gpg signatures validate against the public keyring
#   - DNF repomd.xml.asc signature validates
#   - .deb and .rpm package signatures validate
#   - package layouts are correct
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

read_version
DEB_NAME="retro-tv_${VERSION_NAME}-${VERSION_CODE}_amd64.deb"
RPM_NAME="retro-tv-${VERSION_NAME}-${VERSION_CODE}.x86_64.rpm"
RPM_FILE="$(find "$PACKAGES_DIR" -maxdepth 1 -type f \
    -name "retro-tv-${VERSION_NAME}-${VERSION_CODE}*.x86_64.rpm" -print -quit 2>/dev/null || true)"
if [[ -z "$RPM_FILE" ]]; then
    RPM_FILE="$PACKAGES_DIR/$RPM_NAME"
fi
PASS=1

check() {
    if eval "$*" >/dev/null 2>&1; then echo "  [OK] $*"; else echo "  [FAIL] $*"; PASS=0; fi
}

echo "== package presence =="
check "test -f '$PACKAGES_DIR/$DEB_NAME'"
check "test -f '$RPM_FILE'"
check "test -f '$PACKAGES_DIR/SHA256SUMS'"
check "test -f '$REPOSITORY_DIR/apt/dists/stable/InRelease'"
check "test -f '$REPOSITORY_DIR/apt/dists/stable/Release.gpg'"
check "test -f '$REPOSITORY_DIR/apt/dists/stable/Release'"
check "test -f '$REPOSITORY_DIR/apt/dists/stable/main/binary-amd64/Packages.gz'"
check "test -f '$REPOSITORY_DIR/apt/retro-tv-archive-keyring.gpg'"
check "test -f '$REPOSITORY_DIR/dnf/repodata/repomd.xml'"
check "test -f '$REPOSITORY_DIR/dnf/repodata/repomd.xml.asc'"

echo "== checksums (SHA256SUMS) =="
check "cd '$PACKAGES_DIR' && sha256sum -c SHA256SUMS"

echo "== APT repo signature chain =="
check "gpgv --keyring '$REPOSITORY_DIR/apt/retro-tv-archive-keyring.gpg' '$REPOSITORY_DIR/apt/dists/stable/InRelease'"
check "cd '$REPOSITORY_DIR/apt/dists/stable' && gpgv --keyring '$REPOSITORY_DIR/apt/retro-tv-archive-keyring.gpg' Release.gpg Release"

echo "== DNF repo signature =="
check "cd '$REPOSITORY_DIR/dnf' && gpg --verify repodata/repomd.xml.asc repodata/repomd.xml"

echo "== .deb integrity and signature =="
check "dpkg-deb --info '$PACKAGES_DIR/$DEB_NAME'"
check "dpkg-sig --verify '$PACKAGES_DIR/$DEB_NAME'"

echo "== .rpm integrity and signature =="
# rpm --checksig resolves the signer against RPM's own key database, which does
# not automatically see the keyring that setup-gpg.sh imported into gpg.
if command -v rpm >/dev/null 2>&1; then
    rpm --import "$REPOSITORY_DIR/apt/retro-tv-archive-keyring.gpg" 2>/dev/null || true
fi
check "rpm --checksig '$RPM_FILE'"

echo "== bundle layout inside deb =="
check "dpkg-deb -c '$PACKAGES_DIR/$DEB_NAME' | grep -q 'usr/lib/retro-tv/retro_tv$'"
check "dpkg-deb -c '$PACKAGES_DIR/$DEB_NAME' | grep -q 'usr/bin/retro_tv'"
check "dpkg-deb -c '$PACKAGES_DIR/$DEB_NAME' | grep -q 'usr/share/applications/com.retrotv.retro_tv.desktop'"

echo "== .deb carries our expected version =="
check "dpkg-deb -f '$PACKAGES_DIR/$DEB_NAME' Version | grep -q '^${VERSION_NAME}-${VERSION_CODE}\$'"

echo "== .rpm carries our expected version =="
check "rpm -qp --qf '%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\n' '$RPM_FILE' 2>/dev/null | grep -q '${VERSION_NAME}-${VERSION_CODE}'"

if [ "$PASS" -eq 1 ]; then
    echo "verify-release: ALL CHECKS PASSED"
else
    echo "verify-release: SOME CHECKS FAILED" >&2
    exit 1
fi