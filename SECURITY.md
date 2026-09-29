# Security

Retro TV's release pipeline follows these rules. Everything below is enforced
by the CI workflows under `.github/workflows/`.

## Secrets

- The only secrets used on Linux releases are `GPG_PRIVATE_KEY`,
  `GPG_KEY_ID`, and `GPG_PASSPHRASE` (see [keys/README.md](keys/README.md)).
- The private signing key is **never** stored in this repository. CI imports
  it from GitHub Secrets into a throwaway gpg home on the runner.
- The **public** key is committed on purpose so users can verify package
  signatures without fetching it from a random URL first:
  `keys/retro-tv-archive-keyring.gpg` (fingerprint
  `570D2F04129940F1A8561E4C35111918F6D14EA9`). Anyone can verify it was in
  this exact git history via `git log`. The armored copy is
  `keys/retro-tv-public.asc`.
- `scripts/setup-gpg.sh` **fails the build** if any of the three secrets is
  missing, so a half-signed release can never be published silently.
- `.gitignore` blocks `*.key`, `*.private`, `*.secret`, `*.rev`, `.gnupg/`,
  `.env*`, the private-key export temp file, and generated package binaries
  (`*.deb`, `*.rpm`, `*.flatpak`, `*.snap`).

## Supply-chain integrity (Linux packages)

- **APT**: the repository `InRelease`/`Release.gpg` and every `.deb`
  (`dpkg-sig`) are signed. Install instructions pin the keyring via
  `deb [signed-by=...]` — no `apt-key`, no `curl | sh`.
- **DNF**: `repodata/repomd.xml` is signed (`repo_gpgcheck=1`) and every
  `.rpm` is signed (`.rpm` signatures verified in CI with `rpm --checksig`).
- The full signature chain plus an end-to-end `apt-get update / install
  --download-only retro-tv` from the produced repository is re-checked in
  `scripts/verify-release.sh` before anything is published.
- Every artifact is built in CI from source; the `.deb` is the single binary
  that also feeds the Flatpak bundle, so Windows/Linux builds never come from
  untrusted intermediate uploads.

## Runtime posture

- Playback uses the native mpv/libmpv stack (media_kit). No system shell is
  spawned for video; the only external network surfaces are Supabase (RLS +
  security-definer functions, see README) and YouTube stream resolution.
- The app ships no admin credentials or backend secrets; only the public
  Supabase anon key is embedded.
- Versions older than 1.2.1 targeted only Windows-branded packaging; Linux
  packaging is amd64-only and never over-claims arm64 support.

## Reporting

Security issues: open a private issue in the repository or email the
maintainer (see README contact section). Do not file public issues for
vulnerabilities involving the signing key or Supabase keys.