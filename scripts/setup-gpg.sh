#!/usr/bin/env bash
# Import the GPG release-signing key from the GPG_PRIVATE_KEY secret, prove it
# can really sign, and export the public key. GPG_KEY_ID and GPG_PASSPHRASE
# come from secrets too.
#
# SECRET CONTRACT (see keys/README.md, "Secret format")
# ----------------------------------------------------
# GPG_PRIVATE_KEY is accepted in any of these shapes:
#
#   A) an ASCII-armored OpenPGP private key block
#   B) base64 text of an ASCII-armored OpenPGP private key block
#   C) base64 text of a *binary* OpenPGP private key
#   D) base64 text of base64 text of A, B or C
#
# The stored secret is currently D, so the format is DETECTED and never assumed.
# At most MAX_DECODE_LAYERS base64 layers are peeled, stopping as soon as
# ASCII-armored or binary OpenPGP data is recognised, and gpg stays the final
# authority: whatever survives detection is handed straight to `gpg --import`,
# and a failed import fails the build.
#
# BINARY SAFETY
# -------------
# OpenPGP data is binary. It is NEVER captured in a shell variable:
# `decoded="$(base64 --decode ...)"` silently discards every NUL byte and is
# what produced "warning: command substitution: ignored null byte in input"
# followed by "partial length invalid for packet type 63 / Invalid keyring".
# Every decoding step therefore writes to its own 0600 file inside a 0700
# temporary directory, format detection only ever inspects those files, and gpg
# is pointed at the file directly. No key byte, armor block, base64 payload or
# passphrase is ever written to the log.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

: "${GPG_KEY_ID:?Missing GPG_KEY_ID GitHub secret. Review keys/README.md.}"
: "${GPG_PASSPHRASE:?Missing GPG_PASSPHRASE GitHub secret.}"

if [[ -z "${GPG_PRIVATE_KEY:-}" ]]; then
  die "GPG_PRIVATE_KEY is missing or empty"
fi

# Historical override, kept so an operator can pin the old contract explicitly.
# The default is detection, which is what the CI secret actually needs.
GPG_PRIVATE_KEY_FORMAT="${GPG_PRIVATE_KEY_FORMAT:-auto}"
case "$GPG_PRIVATE_KEY_FORMAT" in
  auto|armor|base64) ;;
  *) die "GPG_PRIVATE_KEY_FORMAT must be 'auto', 'armor' or 'base64' (unsupported value given)" ;;
esac

# Bash tracing echoes whole command lines, and the command lines below carry the
# secret and the passphrase. Switch it off for the entire secret-handling
# section and restore it at the very end.
__xtrace_was_on=0
case "$-" in
  *x*) __xtrace_was_on=1 ;;
esac
set +x

# How many base64 layers may be peeled before the input is called invalid. Three
# covers A, B, C and D with a layer of headroom. Deliberately a small fixed
# number, so this can never degrade into an unbounded decode loop.
MAX_DECODE_LAYERS=3

# --- tools -------------------------------------------------------------------
command -v gpg >/dev/null 2>&1 || die "gpg not found on PATH"

# Tools such as dpkg-sig and rpmsign shell out to plain `gpg` without
# --pinentry-mode/--passphrase, so a passphrase-protected key would make them
# prompt on a tty that does not exist in CI. Enable loopback pinentry and cache
# the passphrase in gpg-agent instead; the cached entry then satisfies every
# later plain `gpg` invocation in this job.
GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
export GNUPGHOME
cat > "$GNUPGHOME/gpg-agent.conf" <<'AGENTCONF'
allow-loopback-pinentry
default-cache-ttl 7200
max-cache-ttl 7200
AGENTCONF
gpgconf --kill gpg-agent 2>/dev/null || true

# --- secure scratch space ----------------------------------------------------
# One 0700 directory holds every intermediate file. umask 077 means even a file
# created between mktemp and chmod is never briefly readable. The EXIT trap
# covers the success path; HUP/INT/TERM cover an interrupted run, so decoded key
# material is never left behind on disk.
umask 077
TMP_DIR="$(mktemp -d)"
chmod 700 "$TMP_DIR"
cleanup() { rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

# --- sanitized metadata, safe to print --------------------------------------
log "GPG_PRIVATE_KEY is present"
log "input length: ${#GPG_PRIVATE_KEY} characters"
log "GNUPGHOME=$GNUPGHOME"
log "GPG_PRIVATE_KEY_FORMAT: $GPG_PRIVATE_KEY_FORMAT"
# sed reads the whole stream instead of exiting early, so gpg is never killed by
# SIGPIPE under `set -o pipefail`.
log "gpg version: $(gpg --version 2>/dev/null | sed -n '1p')"

# --- binary-safe helpers -----------------------------------------------------
# Each of these inspects a FILE. None of them reads key data into a variable.

# base64 -d straight to the destination file. GNU coreutils spells it --decode,
# BSD/macOS only accepts -d, openssl is the last resort. The exit status is the
# caller's to check: a decoding error is never ignored.
b64_decode() {
    local src="$1" dst="$2"
    if printf '' | base64 --decode >/dev/null 2>&1; then
        base64 --decode < "$src" > "$dst"
    elif printf '' | base64 -d >/dev/null 2>&1; then
        base64 -d < "$src" > "$dst"
    else
        openssl base64 -d -A -in "$src" -out "$dst"
    fi
}

# Format A: the ASCII-armored private key block itself. grep reads the file, so
# not one key byte is ever held in a shell variable.
is_armored_private_key() {
    grep -aq '^-----BEGIN PGP PRIVATE KEY BLOCK-----' "$1"
}

# Some other PGP armor block (a public key, a detached signature). Worth naming:
# on its own gpg would only say "no valid OpenPGP data found".
is_other_pgp_armor() {
    grep -aq '^-----BEGIN PGP ' "$1"
}

# Layer detection: is the whole file one base64 payload? Whitespace is stripped
# into a scratch file first (base64 secrets are often wrapped), and the payload
# must be non-empty, stay inside the base64 alphabet and have a length that is a
# multiple of 4. Binary OpenPGP data, armor and free text each fail at least one
# of those tests, so this fires on real base64 text only.
is_base64_text() {
    local file="$1" stripped="$TMP_DIR/.b64-probe" length
    tr -d ' \t\r\n\v\f' < "$file" > "$stripped"
    [[ -s "$stripped" ]] || return 1
    grep -aqE '^[A-Za-z0-9+/]+={0,2}$' "$stripped" || return 1
    length="$(wc -c < "$stripped")"
    (( length % 4 == 0 )) || return 1
    return 0
}

# --- write the secret once, verbatim -----------------------------------------
# printf '%s' keeps the value data-only (no format interpretation) and adds no
# newline. The content is never echoed back.
INPUT_FILE="$TMP_DIR/input"
printf '%s' "$GPG_PRIVATE_KEY" > "$INPUT_FILE"
chmod 600 "$INPUT_FILE"
KEY_FILE="$INPUT_FILE"
unset GPG_PRIVATE_KEY

# --- peel base64 layers until real OpenPGP data appears ----------------------
layers=0
min_layers=0
detected=""
case "$GPG_PRIVATE_KEY_FORMAT" in
  base64) min_layers=1 ;;
esac

while :; do
    if is_armored_private_key "$KEY_FILE"; then
        detected="ascii-armor"
        break
    fi
    if (( layers < min_layers )); then
        # Explicit GPG_PRIVATE_KEY_FORMAT=base64: decode once even when the file
        # does not look like base64, so a malformed secret fails loudly here
        # instead of being handed to gpg.
        next_file="$TMP_DIR/decoded.$(( layers + 1 ))"
        : > "$next_file"
        chmod 600 "$next_file"
        if ! b64_decode "$KEY_FILE" "$next_file"; then
            detected="decode-failed"
            break
        fi
        layers=$(( layers + 1 ))
        KEY_FILE="$next_file"
        log "decoded layer ${layers}: $(wc -c < "$KEY_FILE") bytes"
        continue
    fi
    if [[ "$GPG_PRIVATE_KEY_FORMAT" == armor ]]; then
        detected="armor-missing"
        break
    fi
    if is_base64_text "$KEY_FILE"; then
        # The payload is base64 text again, i.e. the secret is base64-encoded
        # twice (or more). Decode the next layer and classify that result,
        # instead of handing base64 text to gpg - which is exactly what made the
        # build fail with "partial length invalid for packet type 63".
        if (( layers >= MAX_DECODE_LAYERS )); then
            detected="layer-limit"
            break
        fi
        next_file="$TMP_DIR/decoded.$(( layers + 1 ))"
        : > "$next_file"
        chmod 600 "$next_file"
        if ! b64_decode "$KEY_FILE" "$next_file"; then
            detected="decode-failed"
            break
        fi
        layers=$(( layers + 1 ))
        KEY_FILE="$next_file"
        log "detected base64 text, decoded layer ${layers}: $(wc -c < "$KEY_FILE") bytes"
        continue
    fi
    if is_other_pgp_armor "$KEY_FILE"; then
        detected="wrong-pgp-armor"
        break
    fi
    # Neither armor nor base64 text: assume binary OpenPGP and let gpg decide.
    detected="binary-opengep"
    break
done

log "decoded key material: $(wc -c < "$KEY_FILE") bytes, file mode $(stat -c '%a' "$KEY_FILE")"
log "base64 layers decoded: $layers"

case "$detected" in
    ascii-armor)
        log "detected key format: ASCII-armored PGP private key"
        ;;
    binary-opengep)
        log "detected key format: binary OpenPGP private key"
        ;;
    wrong-pgp-armor)
        die "GPG_PRIVATE_KEY holds a PGP armor block, but not a PRIVATE KEY block"
        ;;
    armor-missing)
        die "GPG_PRIVATE_KEY is not ASCII-armored (GPG_PRIVATE_KEY_FORMAT=armor)"
        ;;
    decode-failed)
        die "ERROR: GPG_PRIVATE_KEY is not valid Base64 or ASCII-armored OpenPGP data"
        ;;
    layer-limit)
        die "ERROR: GPG_PRIVATE_KEY is still base64 text after ${MAX_DECODE_LAYERS} decoding layers; expected Base64 or ASCII-armored OpenPGP data"
        ;;
    *)
        die "internal error: unknown key format classification"
        ;;
esac

# --- gpg is the authoritative parser ----------------------------------------
# gpg reads the file itself; the key bytes never pass through a shell variable.
import_err="$TMP_DIR/import.err"
set +e
gpg --batch --quiet --import "$KEY_FILE" 2>"$import_err"
import_status=$?
set -e
log "gpg --import exit status: $import_status"
if (( import_status != 0 )); then
    # Only gpg's own "gpg:"/"gpg-agent:" status lines are echoed, after redacting
    # armor delimiters and any long base64-looking run, so no key bytes can reach
    # the log. gpg never echoes key material in these messages.
    echo "[build] gpg import diagnostics (key material redacted):" >&2
    sed -e 's/-----BEGIN PGP [A-Z ]*-----/[ARMOR REDACTED]/g' \
        -e 's/-----END PGP [A-Z ]*-----/[ARMOR REDACTED]/g' \
        -e 's/[A-Za-z0-9+/]\{60,\}/[LONG BASE64 RUN REDACTED]/g' \
        "$import_err" | grep -E '^(gpg|gpg-agent):' >&2 || true
    die "failed to import GPG private key (detected format: $detected)"
fi
log "GPG private key imported successfully"

# --- the configured key id must be one of the imported SECRET keys -----------
# --list-secret-keys emits colon-delimited metadata (key ids, fingerprints),
# never private key packets, so the resolved fingerprint is safe to log.
secret_key_count="$(gpg --batch --with-colons --list-secret-keys 2>/dev/null \
    | grep -c '^sec:')" || secret_key_count=0
if (( secret_key_count < 1 )); then
    die "gpg reports no secret key after import"
fi
log "imported secret keys: $secret_key_count"

resolved_fingerprint="$(gpg --batch --with-colons --list-secret-keys "$GPG_KEY_ID" 2>/dev/null \
    | awk -F: '$1=="fpr"{print $10; exit}')" || resolved_fingerprint=""
if [[ -z "$resolved_fingerprint" ]]; then
    die "configured GPG_KEY_ID does not match an imported secret key"
fi
log "imported signing key fingerprint: $resolved_fingerprint"

# --- the key must really sign ------------------------------------------------
# The passphrase is only ever handed to gpg as an argument (the loopback
# mechanism above); it is never printed, echoed or traced. The detached
# signature is created, verified and deleted without ever being displayed.
test_err="$TMP_DIR/signing.err"
TEST_FILE="$TMP_DIR/test.txt"
TEST_SIG="$TMP_DIR/test.txt.asc"
printf '%s\n' 'Retro TV GPG CI signing test' > "$TEST_FILE"
chmod 600 "$TEST_FILE"

if ! gpg --batch --yes --quiet --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
        --local-user "$GPG_KEY_ID" --armor --detach-sign \
        --output "$TEST_SIG" "$TEST_FILE" 2>"$test_err"; then
    echo "[build] gpg signing-test diagnostics (key material redacted):" >&2
    sed -e 's/[A-Za-z0-9+/]\{60,\}/[LONG BASE64 RUN REDACTED]/g' \
        "$test_err" | grep -E '^(gpg|gpg-agent):' >&2 || true
    rm -f -- "$TEST_FILE" "$TEST_SIG" "$test_err"
    die "signing test failed: GPG_KEY_ID '$GPG_KEY_ID' could not produce a detached signature (wrong passphrase, expired or unusable key?)"
fi
log "signing test: detached signature created ($(wc -c < "$TEST_SIG") bytes, contents not shown)"

if ! gpg --batch --quiet --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" \
        --verify "$TEST_SIG" "$TEST_FILE" >/dev/null 2>"$test_err"; then
    echo "[build] gpg verification diagnostics (key material redacted):" >&2
    sed -e 's/[A-Za-z0-9+/]\{60,\}/[LONG BASE64 RUN REDACTED]/g' \
        "$test_err" | grep -E '^(gpg|gpg-agent):' >&2 || true
    rm -f -- "$TEST_FILE" "$TEST_SIG" "$test_err"
    die "signature verification failed for the signing test"
fi
log "signing test: PASS (signature verified)"

# The signing test is also the passphrase-cache warm-up that the later plain
# `gpg` calls from dpkg-sig/rpmsign rely on.
rm -f -- "$TEST_FILE" "$TEST_SIG" "$test_err"
log "signing test artifacts removed"

log "gpg ready: $GPG_KEY_ID"

# Also export the public key so downstream scripts can publish it.
mkdir -p "$BUILD_DIR"
gpg --batch --export --armor "$GPG_KEY_ID" > "$BUILD_DIR/release.asc"
gpg --batch --export "$GPG_KEY_ID" > "$BUILD_DIR/release.gpg"
log "public key exported to $BUILD_DIR/release.asc and $BUILD_DIR/release.gpg"

# Secret handling is over; put back any tracing the caller had enabled.
if (( __xtrace_was_on )); then
    set -x
fi