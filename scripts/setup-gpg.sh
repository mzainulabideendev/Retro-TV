#!/usr/bin/env bash
# Import the GPG release-signing key from the GPG_PRIVATE_KEY secret and
# verify key availability. GPG_KEY_ID and GPG_PASSPHRASE come from secrets too.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

: "${GPG_PRIVATE_KEY:?Missing GPG_PRIVATE_KEY GitHub secret. Review keys/README.md and add it under Settings -> Secrets and variables -> Actions.}"
: "${GPG_KEY_ID:?Missing GPG_KEY_ID GitHub secret.}"
: "${GPG_PASSPHRASE:?Missing GPG_PASSPHRASE GitHub secret.}"

umask 077
KEYFILE="$(mktemp)"
trap 'rm -f "$KEYFILE"' EXIT

printf '%s\n' "$GPG_PRIVATE_KEY" | base64 -d > "$KEYFILE"
gpg --batch --quiet --import "$KEYFILE" 2>/dev/null || die "failed to import GPG_PRIVATE_KEY"
rm -f "$KEYFILE"

gpg --batch --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
    --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1 \
    || die "GPG_KEY_ID '$GPG_KEY_ID' not found among imported secret keys"

FINGERPRINT="$(gpg --batch --with-colons --list-keys "$GPG_KEY_ID" | awk -F: '$1=="fpr"{print $10; exit}')"
log "gpg ready: $FINGERPRINT"

# Also export the public key so downstream scripts can publish it.
gpg --batch --export --armor "$GPG_KEY_ID" > "$BUILD_DIR/release.asc"
gpg --batch --export "$GPG_KEY_ID" > "$BUILD_DIR/release.gpg"