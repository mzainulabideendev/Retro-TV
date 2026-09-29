#!/usr/bin/env bash
# Build retro-tv-<name>-<code>.<arch>.rpm by packing the Flutter Linux bundle
# (binary-pack spec). Requires: rpm-build, gtk3-devel-free desktop/icon data
# shipped from the source tree (desktop, icon, metainfo, LICENSE) copied into
# SOURCES by this script.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

read_version
command -v rpmbuild >/dev/null 2>&1 || die "rpmbuild not found (install rpm-build)"
require_bundle
[ -f "$ROOT_DIR/LICENSE" ] || die "LICENSE not found"

TOPDIR="$BUILD_DIR/rpmbuild"
SPEC="$ROOT_DIR/packaging/rpm/retro-tv.spec"
RPMARCH="$(rpm --eval '%{_arch}' 2>/dev/null || echo x86_64)"
[ "$RPMARCH" = "x86_64" ] || log "note: building for $RPMARCH (CI targets amd64)"

rm -rf "$TOPDIR"
mkdir -p "$TOPDIR/SPECS" "$TOPDIR/SOURCES" "$TOPDIR/BUILD" "$TOPDIR/RPMS" "$TOPDIR/SRPMS"
cp "$SPEC" "$TOPDIR/SPECS/"

# Work on a copy of the bundle so the RUNPATH rewrite (absolute build-host path
# -> $ORIGIN) never touches the artifact produced by build-linux.sh.
NORMALIZED="$BUILD_DIR/rpm-bundle"
rm -rf "$NORMALIZED"
cp -r "$BUNDLE_DIR" "$NORMALIZED"
normalize_runpath "$NORMALIZED"
ensure_build_ids "$NORMALIZED"

# Bundle tarball with top directory normalized to "bundle".
tar -C "$NORMALIZED/.." -czf "$TOPDIR/SOURCES/retro-tv-linux-bundle.tar.gz" \
    --transform 's#^[^/]*#bundle#' "$(basename "$NORMALIZED")"

cp "$ROOT_DIR/linux/runner/resources/com.retrotv.retro_tv.desktop" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/linux/runner/resources/app_icon.png" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/packaging/com.retrotv.retro_tv.metainfo.xml" "$TOPDIR/SOURCES/"
cp "$ROOT_DIR/LICENSE" "$TOPDIR/SOURCES/"

rpmbuild -bb \
    --define "_topdir $TOPDIR" \
    --define "_sourcedir $TOPDIR/SOURCES" \
    --define "_specdir $TOPDIR/SPECS" \
    --define "_builddir $TOPDIR/BUILD" \
    --define "_rpmdir $TOPDIR/RPMS" \
    --define "_srcrpmdir $TOPDIR/SRPMS" \
    "$TOPDIR/SPECS/retro-tv.spec"

RPM="$(find "$TOPDIR/RPMS" -name 'retro-tv-*.rpm' ! -name '*.src.rpm' ! -name '*debuginfo*' | head -n1)"
[ -n "$RPM" ] || die "rpmbuild produced no package"
mkdir -p "$PACKAGES_DIR"
cp "$RPM" "$PACKAGES_DIR/"
log "built $(basename "$RPM")"