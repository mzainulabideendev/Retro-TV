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

log "build-flatpak: checking flatpak CLI"
command -v flatpak >/dev/null 2>&1 || die "flatpak CLI not found"
log "build-flatpak: checking deb artifact at $FBSRC"
[ -f "$FBSRC" ] || die "missing $FBSRC (run scripts/build-deb.sh first)"
log "build-flatpak: deb artifact found"

log "build-flatpak: adding flathub remote"
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
log "build-flatpak: flathub remote added"

MANIFEST="$ROOT_DIR/flatpak/com.retrotv.retro_tv.yml"

# Flathub only keeps recent runtime branches, so a branch hardcoded in the
# manifest (e.g. 6.10) can disappear. Resolve the newest available
# org.kde.Platform branch and pin the manifest to that.
detect_kde_branch() {
    local out
    log "build-flatpak: querying flathub for org.kde.Platform branches"
    out="$(flatpak remote-ls --user flathub --arch=x86_64 2>&1)" || {
        log "flatpak remote-ls failed: $out"
        return 1
    }
    log "build-flatpak: remote-ls output (first 20 lines):"
    echo "$out" | head -20
    echo "$out" \
        | grep '^org\.kde\.Platform' \
        | head -n1 \
        | sed -E 's#.*/([0-9][0-9.]*)$#\1#'
}

KDE_BRANCH="$(detect_kde_branch)"
log "build-flatpak: detected KDE branch: '$KDE_BRANCH'"
[ -n "$KDE_BRANCH" ] || die "could not determine an org.kde.Platform branch from flathub"
PINNED="$(sed -n "s/^runtime-version: *'\?\([^']*\)'\?$/\1/p" "$MANIFEST")"
log "build-flatpak: manifest pinned version: '$PINNED'"
if [ "$KDE_BRANCH" != "$PINNED" ]; then
    log "note: manifest pins org.kde.Platform $PINNED; flathub's newest branch is $KDE_BRANCH"
    sed -i -E "s/^(runtime-version: *).*/\1'$KDE_BRANCH'/" "$MANIFEST"
fi
log "using org.kde.Platform//$KDE_BRANCH"

# Install the modern builder + the exact runtimes the manifest needs.
log "build-flatpak: installing org.flatpak.Builder"
flatpak install --user -y --noninteractive flathub org.flatpak.Builder
log "build-flatpak: installing org.kde.Platform and org.kde.Sdk"
flatpak install --user -y --noninteractive flathub org.kde.Platform//"$KDE_BRANCH" org.kde.Sdk//"$KDE_BRANCH"
log "build-flatpak: runtimes installed"

# org.flatpak.Builder is run from the repo root so it can read flatpak/.
log "build-flatpak: running flatpak-builder"
flatpak run --user org.flatpak.Builder \
    --user --install-deps-from=flathub --ccache --force-clean \
    build/flatpak-build flatpak/com.retrotv.retro_tv.yml
log "build-flatpak: flatpak-builder completed"

mkdir -p "$PACKAGES_DIR"
log "build-flatpak: creating flatpak bundle"
flatpak build-bundle "$HOME/.local/share/flatpak/repo" \
    "$PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak" \
    com.retrotv.retro_tv master
log "built $PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak"