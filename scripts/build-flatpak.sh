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

# Install the modern builder + the exact runtimes the manifest needs.
flatpak install --user -y --noninteractive flathub org.flatpak.Builder
flatpak install --user -y --noninteractive flathub org.kde.Platform//6.10 org.kde.Sdk//6.10

# org.flatpak.Builder is run from the repo root so it can read flatpak/.
flatpak run --user org.flatpak.Builder \
    --user --install-deps-from=flathub --ccache --force-clean \
    build/flatpak-build flatpak/com.retrotv.retro_tv.yml

mkdir -p "$PACKAGES_DIR"
flatpak build-bundle "$HOME/.local/share/flatpak/repo" \
    "$PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak" \
    com.retrotv.retro_tv master
log "built $PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak"