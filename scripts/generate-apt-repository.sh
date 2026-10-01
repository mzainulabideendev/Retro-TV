#!/usr/bin/env bash
# Generate the signed APT repository using the standard dists/ + pool/ layout.
#
# Result (published verbatim at https://mzainulabideendev.github.io/Retro-TV/apt/):
#   pool/main/r/retro-tv/retro-tv_<name>-<code>_amd64.deb
#   dists/stable/main/binary-amd64/{Packages,Packages.gz}
#   dists/stable/Release            (signed)
#   dists/stable/InRelease          (signed)
#   dists/stable/Release.gpg
#   retro-tv-archive-keyring.gpg    (public keyring for signed-by=)
#
# Install line:
#   deb [signed-by=/etc/apt/keyrings/retro-tv-archive-keyring.gpg] https://mzainulabideendev.github.io/Retro-TV/apt stable main
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/setup-gpg.sh"

command -v apt-ftparchive >/dev/null 2>&1 || die "apt-ftparchive not found (install apt-utils)"
read_version

APT_DIR="$REPOSITORY_DIR/apt"
DISTS="$APT_DIR/dists/stable"
POOL="$APT_DIR/pool/main/r/retro-tv"

rm -rf "$APT_DIR"
mkdir -p "$DISTS/main/binary-amd64" "$POOL"

shopt -s nullglob
cp "$PACKAGES_DIR"/retro-tv_*.deb "$POOL/"

cd "$APT_DIR"

# Binary package index for amd64.
apt-ftparchive -o APT::FTPArchive::Packages::Architecture=amd64 packages pool/main \
    > "$DISTS/main/binary-amd64/Packages"
gzip -9kf "$DISTS/main/binary-amd64/Packages"

# Release metadata + signature (Suite only: amd64, stable).
apt-ftparchive release \
    -o "APT::FTPArchive::Release::Origin=Retro TV" \
    -o "APT::FTPArchive::Release::Label=Retro TV APT repository" \
    -o "APT::FTPArchive::Release::Suite=stable" \
    -o "APT::FTPArchive::Release::Codename=stable" \
    -o "APT::FTPArchive::Release::Architectures=amd64" \
    -o "APT::FTPArchive::Release::Components=main" \
    "$DISTS" > "$DISTS/Release"

gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
    --digest-algo SHA512 --detach-sign --armor -o "$DISTS/Release.gpg" "$DISTS/Release"
gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
    --digest-algo SHA512 --clearsign -o "$DISTS/InRelease" "$DISTS/Release"

# Machine-readable keyring for /etc/apt/keyrings/retro-tv-archive-keyring.gpg
install -m644 "$BUILD_DIR/release.gpg" "$APT_DIR/retro-tv-archive-keyring.gpg"

# setup-gpg.sh sets umask 077 while handling private material. This generated
# repository is public and APT's sandboxed _apt user must be able to traverse
# directories and read its indexes and packages.
chmod -R a+rX "$APT_DIR"
# The repository parent directories were also created under that umask. Grant
# only traversal, not directory-listing access, on the path leading to the repo.
chmod o+x "$BUILD_DIR" "$REPOSITORY_DIR"

log "apt repository ready at $APT_DIR (dists/stable + pool, InRelease signed)"