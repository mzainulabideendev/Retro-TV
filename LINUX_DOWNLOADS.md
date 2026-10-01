# Retro TV – Linux downloads

All downloads are generated and re-signed automatically on every release tag
(`v*`) by the `Linux Release` workflow, then published to GitHub Pages.

Download index: https://mzainulabideendev.github.io/Retro-TV/

| Artifact | URL |
|---|---|
| APT repo | https://mzainulabideendev.github.io/Retro-TV/apt/ |
| DNF repo | https://mzainulabideendev.github.io/Retro-TV/dnf/ |
| Current .deb | https://mzainulabideendev.github.io/Retro-TV/apt/pool/main/r/retro-tv/retro-tv_1.2.3-7_amd64.deb |
| Current .rpm | https://mzainulabideendev.github.io/Retro-TV/dnf/retro-tv-1.2.3-7.x86_64.rpm |
| Checksums | https://mzainulabideendev.github.io/Retro-TV/SHA256SUMS |
| Release assets (incl. .flatpak) | https://github.com/mzainulabideendev/Retro-TV/releases |

## Repo files

- APT (standard Debian archive layout): `dists/stable/main/binary-amd64/{Packages,Packages.gz}`,
  `dists/stable/{Release,Release.gpg,InRelease}`, `pool/main/r/retro-tv/*.deb`,
  `retro-tv-archive-keyring.gpg`
- DNF: `retro-tv-<name>-<code>.x86_64.rpm`, `repodata/repomd.xml`,
  `repodata/repomd.xml.asc` (signed with key
  `570D2F04129940F1A8561E4C35111918F6D14EA9`), `REPO-METADATA-PUBLIC-KEY.asc`
- `SHA256SUMS`: hashes of the .deb/.rpm/.flatpak artifacts

## Naming / versioning

pubspec `version: 1.2.3+7` maps to:
- .deb: `retro-tv_1.2.3-7_amd64.deb`
- .rpm: `retro-tv-1.2.3-7.x86_64.rpm`
- pkg.tar.zst (AUR build): `retro-tv-1.2.3-7-x86_64.pkg.tar.zst`
- Flatpak bundle: `RetroTV-1.2.3.7.flatpak`

## Signature policy

- APT: signed `InRelease` + `Release.gpg`; `.deb` files signed with `dpkg-sig`.
- DNF: signed `repomd.xml` (`.asc`); `.rpm` files signed with `rpmsign`.
- Key: `570D2F04129940F1A8561E4C35111918F6D14EA9`, see `keys/README.md`.
  Private key never stored in repo.

## Not yet published here

- **Arch/AUR**: recipe in `packaging/arch/PKGBUILD`; publish the same file to
  the AUR manually when ready (requires an Arch/aurweb account).
- **Snap**: recipe in `snap/snapcraft.yaml`; sorting out the Snap Store
  account + CI snapcraft builds is a separate step.
- **Flathub**: bundle is attached to GitHub Releases; uploading to Flathub
  requires a review process and is tracked separately.