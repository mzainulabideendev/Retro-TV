#!/usr/bin/env bash
# Full DNF end-to-end install test (must run as root inside a Fedora/RHEL
# container or VM). Validates the produced DNF repository + signed .rpm:
#   1. import our public key
#   2. register the repository (gpgcheck + repo_gpgcheck=1)
#   3. dnf install retro-tv (resolves mpv-libs/gtk3 from Fedora repos)
#   4. verify executable + desktop entry
#   5. rpm -V (verify installed files)
#   6. dnf remove retro-tv
#
# Usage: test-dnf-install.sh <dnf-repo-dir>
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "test-dnf-install: must run as root" >&2; exit 1; }

DNF_DIR="${1:?usage: test-dnf-install.sh <dnf-repo-dir>}"

rpm --import "$DNF_DIR/REPO-METADATA-PUBLIC-KEY.asc"

cat > /etc/yum.repos.d/retro-tv-test.repo <<EOF
[retro-tv]
name=Retro TV (CI test)
baseurl=file://$DNF_DIR
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://$DNF_DIR/REPO-METADATA-PUBLIC-KEY.asc
EOF

cleanup() { rm -f /etc/yum.repos.d/retro-tv-test.repo; }
trap cleanup EXIT

echo "[1/6] resolve metadata"
# DNF keeps repository-metadata key trust separate from RPM's package key DB.
# Accept the configured gpgkey non-interactively while keeping both signature
# checks enabled in the repository configuration above.
dnf makecache -y || { echo "test-dnf-install: dnf makecache FAILED" >&2; exit 1; }
# `dnf list` is part of core dnf; `repoquery` needs dnf-plugins-core which is
# not present in the minimal CI image.
dnf list --available retro-tv || { echo "test-dnf-install: package not found in repo" >&2; exit 1; }

echo "[2/6] install retro-tv"
dnf install -y retro-tv || { echo "test-dnf-install: dnf install FAILED" >&2; exit 1; }

echo "[3/6] verify executable + desktop entry"
test -x /usr/bin/retro_tv || { echo "test-dnf-install: /usr/bin/retro_tv missing" >&2; exit 1; }
RPM_LIBDIR="$(rpm --eval '%{_libdir}')"
test -x "$RPM_LIBDIR/retro-tv/retro_tv" \
    || { echo "test-dnf-install: $RPM_LIBDIR/retro-tv/retro_tv missing" >&2; exit 1; }
test -f /usr/share/applications/com.retrotv.retro_tv.desktop \
    || { echo "test-dnf-install: desktop entry missing" >&2; exit 1; }

echo "[4/6] verify installed files"
rpm -V retro-tv || { echo "test-dnf-install: rpm -V reported problems" >&2; exit 1; }

echo "[5/6] verify repository RPM signature"
rpm --checksig --verbose "$DNF_DIR"/retro-tv-*.rpm \
    || { echo "test-dnf-install: RPM package signature NOT OK" >&2; exit 1; }

echo "[6/6] remove retro-tv"
dnf remove -y retro-tv || { echo "test-dnf-install: dnf remove FAILED" >&2; exit 1; }

echo "test-dnf-install: PASS (installed retro-tv and removed it)"