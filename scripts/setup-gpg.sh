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

# Tools such as dpkg-sig and rpmsign shell out to plain `gpg` without
# --pinentry-mode/--passphrase, so a passphrase-protected key would make them
# prompt on a tty that does not exist in CI. Enable loopback pinentry and cache
# the passphrase in gpg-agent instead; the cached entry then satisfies every
# later plain `gpg` invocation in this job.
GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
mkdir -p "$GNUPGHOME"
cat > "$GNUPGHOME/gpg-agent.conf" <<'AGENTCONF'
allow-loopback-pinentry
default-cache-ttl 7200
max-cache-ttl 7200
AGENTCONF
gpgconf --kill gpg-agent 2>/dev/null || true

printf '%s\n' "$GPG_PRIVATE_KEY" | base64 -d > "$KEYFILE"

# --- diagnostics: metadata only, never key material -----------------------
# The import used to run with stderr sent to /dev/null, so a failure surfaced
# as a bare "failed to import GPG_PRIVATE_KEY" with no reason attached. The
# checks below report only lengths, formats and gpg's own status lines. The
# private key, the passphrase and the decoded key file are never echoed, and
# the decoded file is only ever inspected through its armor header.
log "GPG_PRIVATE_KEY is present, ${#GPG_PRIVATE_KEY} characters"
log "GNUPGHOME=${GNUPGHOME}"
command -v gpg >/dev/null 2>&1 || die "gpg not found on PATH"
gpg --version
log "decoded key material: $(wc -c < "$KEYFILE") bytes, file mode $(stat -c '%a' "$KEYFILE")"
# 37 bytes is exactly the "-----BEGIN PGP PRIVATE KEY BLOCK-----" armor header.
# Reading it with head -c keeps binary key data out of the shell variable; any
# NUL bytes are discarded by command substitution, which is harmless here
# because a non-armored key simply fails the case below.
armor_header="$(head -c 37 "$KEYFILE" 2>/dev/null || true)"
case "$armor_header" in
  "-----BEGIN PGP PRIVATE KEY BLOCK-----")
    log "decoded format: ASCII-armored PGP private key (matches the documented contract)" ;;
  "-----BEGIN PGP PUBLIC KEY BLOCK-----")
    log "decoded format: ASCII-armored PGP PUBLIC key - this is NOT a private key" ;;
  *)
    log "decoded format: NOT ASCII-armored (no PGP armor header in the first 37 bytes)" ;;
esac
# A base64 secret that was itself base64-encoded once too often decodes
# cleanly to more base64 text, which gpg cannot parse. Detect that without
# decoding or printing anything: valid base64 is a single unbroken alphabet.
if tr -d '\n\r' < "$KEYFILE" | grep -qE '^[A-Za-z0-9+/=]+$' \
   && ! grep -q 'BEGIN PGP' "$KEYFILE"; then
  log "decoded content looks like base64 text, i.e. the secret may be base64-encoded twice"
fi

# Capture gpg's diagnostics instead of discarding them. On failure only gpg's
# own "gpg:"/"gpg-agent:" status lines are echoed, after redacting any armor
# delimiter and any long base64-looking run, so no key bytes can reach the log.
import_err="$(mktemp)"
set +e
gpg --batch --quiet --import "$KEYFILE" 2>"$import_err"
import_status=$?
set -e
log "gpg --import exit status: $import_status"
if [[ "$import_status" -ne 0 ]]; then
  echo "[build] gpg import diagnostics (key material redacted):" >&2
  sed -e 's/-----BEGIN PGP [A-Z ]*-----/[ARMOR REDACTED]/g' \
      -e 's/-----END PGP [A-Z ]*-----/[ARMOR REDACTED]/g' \
      -e 's/[A-Za-z0-9+/]\{60,\}/[LONG BASE64 RUN REDACTED]/g' \
      "$import_err" | grep -E '^(gpg|gpg-agent):' >&2 || true
  rm -f "$import_err"
  die "failed to import GPG_PRIVATE_KEY"
fi
rm -f "$import_err"

gpg --batch --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
    --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1 \
    || die "GPG_KEY_ID '$GPG_KEY_ID' not found among imported secret keys"

# Prime the agent cache with one loopback signature.
printf 'retrotv\n' | gpg --batch --yes --quiet --pinentry-mode loopback \
    --passphrase "$GPG_PASSPHRASE" --local-user "$GPG_KEY_ID" \
    --armor --clearsign --output /dev/null \
    || die "failed to unlock GPG key '$GPG_KEY_ID' with the provided passphrase"

FINGERPRINT="$(gpg --batch --with-colons --list-keys "$GPG_KEY_ID" | awk -F: '$1=="fpr"{print $10; exit}')"
log "gpg ready: $FINGERPRINT"

# Also export the public key so downstream scripts can publish it.
gpg --batch --export --armor "$GPG_KEY_ID" > "$BUILD_DIR/release.asc"
gpg --batch --export "$GPG_KEY_ID" > "$BUILD_DIR/release.gpg"