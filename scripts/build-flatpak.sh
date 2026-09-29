#!/usr/bin/env bash
# Build RetroTV-<name>.<code>.flatpak from the signed .deb using the proven
# Flathub module set (libmpv.yml). Requires the flatpak CLI (Debian/Ubuntu
# ship flatpak-builder only as a stub → we use the org.flatpak.Builder app).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

read_version
DEB_NAME="retro-tv_${VERSION_NAME}-${VERSION_CODE}_amd64.deb"
FBSRC="$PACKAGES_DIR/$DEB_NAME"
FBOUT="$BUILD_DIR/flatpak-build"

command -v flatpak >/dev/null 2>&1 || die "flatpak CLI not found"
[ -f "$FBSRC" ] || die "missing $FBSRC (run scripts/build-deb.sh first)"

flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

MANIFEST="$ROOT_DIR/flatpak/com.retrotv.retro_tv.yml"

# Flathub only keeps recent runtime branches, so a branch hardcoded in the
# manifest (e.g. 6.10) can disappear. Resolve the newest available
# org.kde.Platform branch and pin the manifest to that.
detect_kde_branch() {
    flatpak remote-ls --user flathub --arch=x86_64 --columns=ref 2>/dev/null \
        | sed -n 's#^app/org\.kde\.Platform/x86_64/\([0-9][0-9.]*\)$#\1#p' \
        | sort -V | tail -n1
}

KDE_BRANCH="$(detect_kde_branch)"
[ -n "$KDE_BRANCH" ] || die "could not determine an org.kde.Platform branch from flathub"
PINNED="$(sed -n "s/^runtime-version: *'\?\([^']*\)'\?$/\1/p" "$MANIFEST")"
if [ "$KDE_BRANCH" != "$PINNED" ]; then
    log "note: manifest pins org.kde.Platform $PINNED; flathub's newest branch is $KDE_BRANCH"
    sed -i -E "s/^(runtime-version: *).*/\1'$KDE_BRANCH'/" "$MANIFEST"
fi
log "using org.kde.Platform//$KDE_BRANCH"

# Install the modern builder + the exact runtimes the manifest needs.
flatpak install --user -y --noninteractive flathub org.flatpak.Builder
flatpak install --user -y --noninteractive flathub org.kde.Platform//"$KDE_BRANCH" org.kde.Sdk//"$KDE_BRANCH"

# org.flatpak.Builder is run from the repo root so it can read flatpak/.
flatpak run --user org.flatpak.Builder \
    --user --install-deps-from=flathub --ccache --force-clean \
    build/flatpak-build flatpak/com.retrotv.retro_tv.yml

mkdir -p "$PACKAGES_DIR"
flatpak build-bundle "$HOME/.local/share/flatpak/repo" \
    "$PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak" \
    com.retrotv.retro_tv master
log "built $PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak"