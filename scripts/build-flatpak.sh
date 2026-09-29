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
    local kde_branch=""
    local manifest_branch=""
    local candidate_branches=()
    
    # Read the pinned version from manifest first
    manifest_branch="$(sed -n "s/^runtime-version: *'\?\([^']*\)'\?$/\1/p" "$MANIFEST")"
    log "build-flatpak: manifest pins org.kde.Platform version: '${manifest_branch}'" >&2
    
    # Strategy: Try the manifest's pinned version first, then fallback to known supported branches
    # Known KDE Platform branches (newest first) that are commonly available on Flathub
    local known_branches=("6.10" "6.9" "6.8" "6.7" "6.6" "6.5" "6.4" "6.3" "6.2" "6.1" "6.0" "5.15" "5.14" "5.13")
    
    # If manifest has a version, prioritize it
    if [ -n "$manifest_branch" ]; then
        candidate_branches+=("$manifest_branch")
    fi
    
    # Add known branches (avoid duplicates)
    for branch in "${known_branches[@]}"; do
        local found=0
        for existing in "${candidate_branches[@]}"; do
            if [ "$existing" = "$branch" ]; then
                found=1
                break
            fi
        done
        if [ $found -eq 0 ]; then
            candidate_branches+=("$branch")
        fi
    done
    
    log "build-flatpak: will try KDE Platform branches in order: ${candidate_branches[*]}" >&2
    
    # Verify each candidate branch exists on Flathub by checking both Platform and SDK
    for branch in "${candidate_branches[@]}"; do
        log "build-flatpak: checking if KDE Platform $branch exists on Flathub..." >&2
        
        # Check if Platform runtime exists
        set +e
        flatpak remote-info --user flathub "org.kde.Platform/x86_64/${branch}" >/dev/null 2>&1
        local platform_result=$?
        flatpak remote-info --user flathub "org.kde.Sdk/x86_64/${branch}" >/dev/null 2>&1
        local sdk_result=$?
        set -e
        
        if [ $platform_result -eq 0 ] && [ $sdk_result -eq 0 ]; then
            log "build-flatpak: VERIFIED: KDE Platform $branch and SDK $branch both exist on Flathub" >&2
            printf '%s\n' "$branch"
            return 0
        elif [ $platform_result -eq 0 ]; then
            log "build-flatpak: WARNING: Platform $branch exists but SDK $branch missing, trying next..." >&2
        else
            log "build-flatpak: KDE Platform $branch not found on Flathub, trying next..." >&2
        fi
    done
    
    log "build-flatpak: ERROR: no verified KDE Platform/SDK branch found on Flathub" >&2
    return 1
}

log "build-flatpak: calling detect_kde_branch..." >&2
# Call function directly, capture stdout to KDE_BRANCH, let stderr (logs) pass through
KDE_BRANCH="$(detect_kde_branch)"
DETECT_RESULT=$?
if [ $DETECT_RESULT -ne 0 ]; then
    log "build-flatpak: ERROR: detect_kde_branch failed with exit code $DETECT_RESULT" >&2
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

# Diagnostic output for debugging
log "build-flatpak: Flatpak diagnostics:"
log "  Flatpak: $(flatpak --version 2>/dev/null || echo 'not found')"
log "  flatpak-builder: $(flatpak-builder --version 2>/dev/null || echo 'not found')"
log "  dbus-run-session: $(command -v dbus-run-session || echo 'not found')"
log "  DISPLAY: ${DISPLAY:-<unset>}"
log "  DBUS_SESSION_BUS_ADDRESS: ${DBUS_SESSION_BUS_ADDRESS:-<unset>}"
log "  XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-<unset>}"
log "  HOME: $HOME"

# Diagnostics with explicit error handling to avoid pipefail issues
log "  User runtimes:" >&2
flatpak --user list --runtime 2>/dev/null | head -20 || true
log "  User apps:" >&2
flatpak --user list --app 2>/dev/null | head -10 || true

log "build-flatpak: ABOUT TO EXECUTE flatpak-builder via dbus-run-session" >&2

# Ensure we have a D-Bus session for headless Flatpak operations
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$UID}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Start a D-Bus session for headless flatpak-builder
if command -v dbus-run-session >/dev/null 2>&1; then
    log "build-flatpak: starting dbus-run-session for flatpak-builder" >&2
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
    dbus-run-session -- flatpak run --user org.flatpak.Builder \
        --user --install-deps-from=flathub --ccache --force-clean \
        build/flatpak-build flatpak/com.retrotv.retro_tv.yml
    BUILDER_RESULT=$?
    if [ $BUILDER_RESULT -ne 0 ]; then
        log "build-flatpak: ERROR: flatpak-builder failed with exit code $BUILDER_RESULT" >&2
        exit $BUILDER_RESULT
    fi
else
    log "build-flatpak: WARNING: dbus-run-session not found, attempting without" >&2
    flatpak run --user org.flatpak.Builder \
        --user --install-deps-from=flathub --ccache --force-clean \
        build/flatpak-build flatpak/com.retrotv.retro_tv.yml
    BUILDER_RESULT=$?
    if [ $BUILDER_RESULT -ne 0 ]; then
        log "build-flatpak: ERROR: flatpak-builder failed with exit code $BUILDER_RESULT" >&2
        exit $BUILDER_RESULT
    fi
fi
log "build-flatpak: flatpak-builder completed" >&2

mkdir -p "$PACKAGES_DIR"
log "build-flatpak: creating flatpak bundle"
flatpak build-bundle "$HOME/.local/share/flatpak/repo" \
    "$PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak" \
    com.retrotv.retro_tv master || die "flatpak build-bundle failed"
log "built $PACKAGES_DIR/RetroTV-${VERSION_NAME}.${VERSION_CODE}.flatpak"