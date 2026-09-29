#!/usr/bin/env bash
# Generate the signed DNF repository (repodata + signed repomd.xml) under
# build/repository/dnf. Published verbatim at
# https://mzainulabideendev.github.io/Retro-TV/dnf/
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/setup-gpg.sh"

command -v createrepo_c >/dev/null 2>&1 || die "createrepo_c not found"
read_version

DNF_DIR="$REPOSITORY_DIR/dnf"
rm -rf "$DNF_DIR"
mkdir -p "$DNF_DIR"

cp "$PACKAGES_DIR"/retro-tv-*.rpm "$DNF_DIR/"
install -m644 "$BUILD_DIR/release.asc" "$DNF_DIR/REPO-METADATA-PUBLIC-KEY.asc"

createrepo_c --pretty "$DNF_DIR"

gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
    --digest-algo SHA512 --detach-sign --armor \
    -o "$DNF_DIR/repodata/repomd.xml.asc" "$DNF_DIR/repodata/repomd.xml"

log "dnf repository ready at $DNF_DIR"