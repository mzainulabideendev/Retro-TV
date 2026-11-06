#!/usr/bin/env bash
# Common helpers for the Retro TV Linux build scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PACKAGES_DIR="$BUILD_DIR/packages"
REPOSITORY_DIR="$BUILD_DIR/repository"
BUNDLE_DIR="$BUILD_DIR/linux/x64/release/bundle"

log()  { printf '[build] %s\n' "$*"; }
die()  { printf '[build] ERROR: %s\n' "$*" >&2; exit 1; }

# Read the version name and build code from pubspec.yaml's version line.
read_version() {
    local line version_line
    version_line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?[[:space:]]*$' "$ROOT_DIR/pubspec.yaml" | head -n1)"
    [ -n "$version_line" ] || die "could not parse version from pubspec.yaml"
    VERSION_LINE="$(echo "$version_line" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]*$//')"
    VERSION_NAME="${VERSION_LINE%%+*}"
    if [[ "$VERSION_LINE" == *"+"* ]]; then
        VERSION_CODE="${VERSION_LINE##*+}"
    else
        VERSION_CODE="0"
    fi
    log "version: name=$VERSION_NAME code=$VERSION_CODE"
}

require_bundle() {
    [ -x "$BUNDLE_DIR/retro_tv" ] || die "Flutter Linux bundle not found at $BUNDLE_DIR. Run scripts/build-linux.sh first."
}

# Flutter bakes an absolute build-host path (…/linux/flutter/ephemeral) into the
# RUNPATH of the bundled plugin .so files and the executable. That path does not
# exist on a user's machine, and rpmbuild refuses to package such binaries
# ("contains an invalid runpath"). Rewrite them to $ORIGIN-relative paths:
#   <libdir>/lib/*.so  -> $ORIGIN
#   <libdir>/retro_tv  -> $ORIGIN/lib
# so the layout works both from /usr/lib/retro-tv and from /app/lib/retro-tv.
normalize_runpath() {
    local root="$1"
    command -v patchelf >/dev/null 2>&1 || die "patchelf not found (apt: patchelf / dnf: patchelf)"

    local so
    while IFS= read -r -d '' so; do
        patchelf --remove-rpath "$so" 2>/dev/null || true
        patchelf --set-rpath '$ORIGIN' "$so"
    done < <(find "$root/lib" -type f -name '*.so*' -print0 2>/dev/null)

    patchelf --remove-rpath "$root/retro_tv" 2>/dev/null || true
    patchelf --set-rpath '$ORIGIN/lib' "$root/retro_tv"
}

# rpmbuild's elf dependency generator fails with "Missing build-id" for binaries
# that have no GNU build-id note. patchelf (and Flutter's prebuilt plugin
# libraries) can end up in that state, so re-add an id where it is missing.
ensure_build_ids() {
    local root="$1" f cmd="" count=0
    # elfbuildid (Fedora elfutils) or eu-build-id (older/other distros) can add
    # a random build-id to an ELF file that lacks one.
    for c in elfbuildid eu-build-id /usr/bin/elfbuildid /usr/bin/eu-build-id; do
        if command -v "$c" >/dev/null 2>&1; then
            cmd="$c"
            break
        fi
    done
    if [ -z "$cmd" ]; then
        log "warning: no elfbuildid/eu-build-id found in PATH; searching /usr/bin..."
        if [ -x /usr/bin/elfbuildid ]; then cmd="/usr/bin/elfbuildid"; fi
        if [ -z "$cmd" ] && [ -x /usr/bin/eu-build-id ]; then cmd="/usr/bin/eu-build-id"; fi
    fi
    [ -n "$cmd" ] || { log "warning: no elfbuildid/eu-build-id found; skipping build-id injection"; return 0; }
    log "ensure_build_ids: using $cmd on $root"
    log "ensure_build_ids: scanning for ELF files..."
    while IFS= read -r -d '' f; do
        log "ensure_build_ids: checking $f"
        if ! readelf -n "$f" 2>/dev/null | grep -q "Build ID"; then
            log "ensure_build_ids: adding build-id to $f"
            "$cmd" -q "$f"
            count=$((count + 1))
        else
            log "ensure_build_ids: $f already has build-id"
        fi
    done < <(find "$root" -type f \( -name '*.so*' -o -name 'retro_tv' \) -print0 2>/dev/null)
    log "ensure_build_ids: processed $count file(s)"
}