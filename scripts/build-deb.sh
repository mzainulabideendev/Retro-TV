#!/usr/bin/env bash
# Build retro-tv_<name>-<code>_amd64.deb from the Flutter Linux bundle.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_bundle
read_version

DEB_VERSION="$VERSION_NAME-$VERSION_CODE"
DEB_NAME="retro-tv_${DEB_VERSION}_amd64.deb"
STAGE="$BUILD_DIR/packages/deb-root"
OUT="$PACKAGES_DIR/$DEB_NAME"

PREFIX=/usr
LIBDIR="$PREFIX/lib/retro-tv"

rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE$LIBDIR" "$STAGE$PREFIX/bin"
mkdir -p "$STAGE$PREFIX/share/applications" "$STAGE$PREFIX/share/metainfo"
mkdir -p "$STAGE$PREFIX/share/icons/hicolor/192x192/apps"
mkdir -p "$STAGE$PREFIX/share/doc/retro-tv"
mkdir -p "$STAGE/DEBIAN"

cp -r "$BUNDLE_DIR/lib" "$STAGE$LIBDIR/"
cp -r "$BUNDLE_DIR/data" "$STAGE$LIBDIR/"
install -m755 "$BUNDLE_DIR/retro_tv" "$STAGE$LIBDIR/retro_tv"
# Drop the build-host RUNPATH baked in by Flutter (see common.sh).
normalize_runpath "$STAGE$LIBDIR"
# Relative symlink (../lib/retro-tv/retro_tv) so the same .deb also works when
# unpacked into /app by the Flatpak manifest (/app/bin -> /app/lib/retro-tv).
ln -s "../lib/retro-tv/retro_tv" "$STAGE$PREFIX/bin/retro_tv"

install -m644 "$ROOT_DIR/linux/runner/resources/com.retrotv.retro_tv.desktop" "$STAGE$PREFIX/share/applications/com.retrotv.retro_tv.desktop"
install -m644 "$ROOT_DIR/linux/runner/resources/app_icon.png" "$STAGE$PREFIX/share/icons/hicolor/192x192/apps/retro-tv.png"
install -m644 "$ROOT_DIR/packaging/com.retrotv.retro_tv.metainfo.xml" "$STAGE$PREFIX/share/metainfo/com.retrotv.retro_tv.metainfo.xml"
install -m644 "$ROOT_DIR/LICENSE" "$STAGE$PREFIX/share/doc/retro-tv/copyright"

# Debian control: fill in the real version and computed installed size.
sed -e "s/^Version: .*/Version: $DEB_VERSION/" "$ROOT_DIR/packaging/deb/control" > "$STAGE/DEBIAN/control"
INSTALLED_SIZE="$(du -sk "$STAGE" | cut -f1)"
sed -i -e "s/^Installed-Size: .*/Installed-Size: $INSTALLED_SIZE/" "$STAGE/DEBIAN/control"
install -m644 "$ROOT_DIR/packaging/deb/postinst" "$STAGE/DEBIAN/postinst"
install -m644 "$ROOT_DIR/packaging/deb/postrm" "$STAGE/DEBIAN/postrm"

dpkg-deb --build --root-owner-group "$STAGE" "$OUT"
log "built $OUT"

# Optional .deb signature (used by the signed APT repository).
if command -v dpkg-sig >/dev/null 2>&1 && [ -n "${GPG_KEY_ID:-}" ]; then
    dpkg-sig --sign builder -k "$GPG_KEY_ID" "$OUT"
    log "signed $OUT with $GPG_KEY_ID"
fi