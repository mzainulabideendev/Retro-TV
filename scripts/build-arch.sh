#!/usr/bin/env bash
# Build the Arch Linux package (retro-tv-<name>-<code>-x86_64.pkg.tar.zst).
#
# Requires a non-root user with `fakeroot` on PATH (makepkg refuses to run as
# root). The official extra/flutter package must be installed. PKGBUILD uses
# sha256sums=('SKIP'); replace it with the real hash after the first v<name>
# release tag exists.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

[ "$(id -u)" -ne 0 ] || die "makepkg refuses to run as root; run as a build user"
command -v makepkg >/dev/null 2>&1 || die "makepkg not found"
read_version

PKG_DIR="$ROOT_DIR/packaging/arch"
PKGDEST="${PKGDEST:-$PACKAGES_DIR}"
mkdir -p "$PKGDEST" "$BUILD_DIR/arch"

cd "$PKG_DIR"
BUILDDIR="$BUILD_DIR/arch" PKGDEST="$PKGDEST" \
    makepkg -f --noconfirm --cleanbuild

log "artifacts in $PKGDEST"
ls -1 "$PKGDEST"/retro-tv-*.pkg.tar.zst 2>/dev/null | sed 's/^/  /'