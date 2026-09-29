# Release signing keys

Retro TV's Linux repositories (APT + DNF) are GPG-signed. The private key is
**never** stored in this repository or on build runners beyond the moment CI
imports it from GitHub Secrets.

## Current key (already generated)

- Fingerprint / key ID: `570D2F04129940F1A8561E4C35111918F6D14EA9`
- UID: `Retro TV <mzainulabideen.dev@gmail.com>`
- Algorithm: RSA 4096, created 2026-09-29, expires 2031-09-28
- Encryption subkey: `798636E0C2F6C7800D2B98C6E775EF4AA2AB92B3`

This repository already contains the **public** key (safe to commit):

- `keys/retro-tv-archive-keyring.gpg` — binary keyring used with `signed-by=`
- `keys/retro-tv-public.asc` — armored public key for manual verification

## One-time GitHub setup (you)

1. On your machine (PowerShell), export the private key to base64 — export to a
   temp file, base64 it, then delete the file (never put it in this repo):
   ```powershell
   gpg --armor --export-secret-keys 570D2F04129940F1A8561E4C35111918F6D14EA9 > "$env:TEMP\retro-tv-secret.asc"
   $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:TEMP\retro-tv-secret.asc"))
   Remove-Item "$env:TEMP\retro-tv-secret.asc"
   Write-Output $b64
   ```
2. Add these three repository secrets under
   `Settings -> Secrets and variables -> Actions`:
   - `GPG_PRIVATE_KEY` – the base64 string printed above
   - `GPG_KEY_ID` – `570D2F04129940F1A8561E4C35111918F6D14EA9`
   - `GPG_PASSPHRASE` – the passphrase you chose when creating the key
3. After the first signed release, the same public key is also published to:
   - APT: `https://mzainulabideendev.github.io/Retro-TV/apt/retro-tv-archive-keyring.gpg`
   - DNF: `https://mzainulabideendev.github.io/Retro-TV/dnf/REPO-METADATA-PUBLIC-KEY.asc`
4. Keep a backup of the key and its revocation certificate somewhere safe
   (gpg saved the cert to `openpgp-revocs.d/570D2F04...rev` on your machine).

## What CI signs

- APT: `dists/stable/Release` + `InRelease` (clearsign) + every `.deb`
  (`dpkg-sig`).
- DNF: `repodata/repomd.xml` (`.asc`) + every `.rpm` (`rpmsign`).
- The Flatpak bundle is distributed unsigned via GitHub Release downloads;
  Flathub publication would add Flathub's own signing.

## Rotation

To rotate: generate a new key, update the three secrets, push a new `v*` tag.
The old public key remains listed in the last repository metadata until the
next release regenerates it.

## Gotcha

`scripts/*.sh` deliberately `die()` with "Missing GPG_* GitHub secret." if any
of the three secrets is missing, so a half-signed release can never be
published silently. CI logs contain only the key ID and SHA256 hashes, never
the private key or passphrase.