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
flatpak --version
log "build-flatpak: checking flatpak-builder"
command -v flatpak-builder >/dev/null 2>&1 || die "flatpak-builder not found"
flatpak-builder --version
log "build-flatpak: checking deb artifact at $FBSRC"
[ -f "$FBSRC" ] || die "missing $FBSRC (run scripts/build-deb.sh first)"
log "build-flatpak: deb artifact found"

log "build-flatpak: adding flathub remote"
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
log "build-flatpak: flathub remote added"
flatpak remotes

MANIFEST="$ROOT_DIR/flatpak/com.retrotv.retro_tv.yml"

# Flathub only keeps recent runtime branches, so a branch hardcoded in the
# manifest (e.g. 6.10) can disappear. Resolve the newest available
# org.kde.Platform branch and pin the manifest to that.
detect_kde_branch() {
    local out kde_branch="" line exit_code
    log "build-flatpak: querying flathub for org.kde.Platform branches"
    set +e
    # First, let's see what remotes we have
    log "build-flatpak: checking configured remotes:"
    flatpak remotes --user
    log "build-flatpak: running remote-ls for flathub..."
    out="$(flatpak remote-ls --user flathub --arch=x86_64 2>&1)"
    exit_code=$?
    set -e
    log "build-flatpak: remote-ls exit code: $exit_code"
    log "build-flatpak: remote-ls FULL output:"
    printf '%s\n' "$out"
    if [ $exit_code -ne 0 ]; then
        log "build-flatpak: WARNING: remote-ls returned non-zero exit code $exit_code, but continuing to parse output"
    fi
    # Extract KDE branch without head to avoid SIGPIPE
    # Try multiple patterns that might appear in remote-ls output
    while IFS= read -r line; do
        # Pattern 1: org.kde.Platform/x86_64/6.10
        if [[ "$line" =~ ^org\.kde\.Platform[[:space:]] ]]; then
            kde_branch="${line%%[[:space:]]*}"
            kde_branch="${kde_branch##*/}"
            log "build-flatpak: found KDE Platform (pattern 1): $kde_branch"
            break
        fi
        # Pattern 2: org.kde.Platform/x86_64/6.10 at start of line
        if [[ "$line" =~ ^org\.kde\.Platform/ ]]; then
            kde_branch="${line##*/}"
            log "build-flatpak: found KDE Platform (pattern 2): $kde_branch"
            break
        fi
        # Pattern 3: any line containing org.kde.Platform
        if [[ "$line" =~ org\.kde\.Platform ]]; then
            # Extract version from something like org.kde.Platform/x86_64/6.10
            if [[ "$line" =~ org\.kde\.Platform/([^/]+)/([0-9.]+) ]]; then
                kde_branch="${BASH_REMATCH[2]}"
                log "build-flatpak: found KDE Platform (pattern 3): $kde_branch"
                break
            fi
        fi
    done <<< "$out"
    if [ -z "$kde_branch" ]; then
        log "build-flatpak: ERROR: could not find org.kde.Platform branch in remote-ls output"
        log "build-flatpak: Available refs containing 'kde' (case-insensitive):"
        printf '%s\n' "$out" | grep -i kde || log "  (none found)"
        return 1
    fi
    printf '%s\n' "$kde_branch"
}

log "build-flatpak: calling detect_kde_branch..."
set +e
KDE_BRANCH="$(detect_kde_branch)"
DETECT_RESULT=$?
set -e
if [ $DETECT_RESULT -ne 0 ]; then
    log "build-flatpak: ERROR: detect_kde_branch failed with exit code $DETECT_RESULT"
    exit $DETECT_RESULT
fi
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
set +e
flatpak install --user -y --noninteractive flathub org.flatpak.Builder
BUILDER_RESULT=$?
set -e
if [ $BUILDER_RESULT -ne 0 ]; then
    log "build-flatpak: ERROR: flatpak install Builder failed with exit code $BUILDER_RESULT"
    exit $BUILDER_RESULT
fi
log "build-flatpak: Builder installed"

log "build-flatpak: installing org.kde.Platform and org.kde.Sdk"
set +e
flatpak install --user -y --noninteractive flathub org.kde.Platform//"$KDE_BRANCH" org.kde.Sdk//"$KDE_BRANCH"
RUNTIME_RESULT=$?
set -e
if [ $RUNTIME_RESULT -ne 0 ]; then
    log "build-flatpak: ERROR: flatpak install runtime/SDK failed with exit code $RUNTIME_RESULT"
    exit $RUNTIME_RESULT
fi
log "build-flatpak: runtimes installed"

# org.flatpak.Builder is run from the repo root so it can read flatpak/.
log "build-flatpak: running flatpak-builder"
flatpak run --user org.flatpak.Builder \
    --user --install-deps-from=flathub --ccache --force-clean \
    build/flatpak-build flatpak/com.retrotv.retro_tv.yml || die "flatpak-builder failed"
log "build-flatpak: flatpak-builder completed"

mkdir -p "$PACKAGES_DIR"
log "build-flatpak: creating flatpak bundle"
flatpak build-bundle "$HOME/.local/share/flatpak/repo" \
    "$PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak" \
    com.retrotv.retro_tv master || die "flatpak build-bundle failed"
log "built $PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak"