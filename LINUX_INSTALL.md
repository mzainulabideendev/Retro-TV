# Installing Retro TV on Linux (amd64)

Current release: **1.2.3** (build 7; tag `v1.2.3`). Requires an x86_64
machine with a display (X11 or Wayland). Releases are signed with GPG key
`570D2F04129940F1A8561E4C35111918F6D14EA9` (`Retro TV <mzainulabideen.dev@gmail.com>`).

The app plays video via the native mpv/libmpv stack, so a `libmpv.so.2`
provider must be present (installed automatically by the package managers):

| Distro family | Tested on | libmpv.so.2 provider |
|---|---|---|
| Debian 12+ / Ubuntu 22.04+ (and Mint) | Debian-style CI container + Ubuntu 24.04 runner | `libmpv2` |
| Ubuntu 20.04 / Debian 11 | NOT supported | only provides libmpv.so.1 |
| Fedora | Fedora 42 CI container | `mpv-libs` |
| Arch | CI build using the official `flutter` package | `libmpv` |

## Option A – APT (Debian / Ubuntu / Linux Mint)

Install the key and add the repository:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://mzainulabideendev.github.io/Retro-TV/apt/retro-tv-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/retro-tv-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/retro-tv-archive-keyring.gpg] https://mzainulabideendev.github.io/Retro-TV/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/retro-tv.list >/dev/null

sudo apt update
sudo apt install retro-tv
```

`gpgcheck` is enforced through the `signed-by` path; APT refuses the repo if
the `InRelease` signature does not validate.

## Option B – DNF (Fedora)

```bash
sudo curl -fsSL https://mzainulabideendev.github.io/Retro-TV/dnf/REPO-METADATA-PUBLIC-KEY.asc \
  -o /etc/pki/rpm-gpg/RPM-GPG-KEY-retro-tv
echo -e '[retro-tv]\nname=Retro TV\nbaseurl=https://mzainulabideendev.github.io/Retro-TV/dnf/\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-retro-tv' \
  | sudo tee /etc/yum.repos.d/retro-tv.repo

sudo dnf install retro-tv
```

## Option C – direct download

- `.deb`: https://mzainulabideendev.github.io/Retro-TV/apt/pool/main/r/retro-tv/retro-tv_1.2.3-7_amd64.deb
- `.rpm`: https://mzainulabideendev.github.io/Retro-TV/dnf/retro-tv-1.2.3-7.x86_64.rpm
- Checksums: https://mzainulabideendev.github.io/Retro-TV/SHA256SUMS
- GitHub Release assets (including the `.flatpak`): https://github.com/mzainulabideendev/Retro-TV/releases

Install a downloaded deb/rpm directly:

```bash
# Debian/Ubuntu
sudo apt install ./retro-tv_1.2.3-7_amd64.deb
# Fedora
sudo dnf install ./retro-tv-1.2.3-7.x86_64.rpm
```

## Option D – Flatpak

After downloading `RetroTV-1.2.3.7.flatpak` from the GitHub release:

```bash
flatpak install --user org.kde.Platform//6.10
flatpak install --user --noninteractive ./RetroTV-1.2.3.7.flatpak
flatpak run com.retrotv.retro_tv
```

## Running

Launch from the application menu (category AudioVideo > Player) or:

```bash
retro_tv
```

The window opens as "Retro TV". Sound uses whatever audio backend the device
provider exposes (PulseAudio/PipeWire/Wayland).

## Updating

- APT: `sudo apt update && sudo apt upgrade`
- DNF: `sudo dnf update retro-tv`
- Manual/Flatpak: re-download the new artifact.

## Uninstalling

```bash
sudo apt remove retro-tv        # or: sudo dnf remove retro-tv
```

## Verifying integrity (optional)

```bash
# APT signed-by ensures this automatically. Manual check:
curl -fsSL https://mzainulabideendev.github.io/Retro-TV/apt/retro-tv-archive-keyring.gpg -o key.gpg
gpgv --keyring key.gpg <(curl -fsSL https://mzainulabideendev.github.io/Retro-TV/apt/InRelease) <(curl -fsSL https://mzainulabideendev.github.io/Retro-TV/apt/Release)
```

## Troubleshooting

- **"error while loading shared libraries: libmpv.so.2"** — install the
  libmpv provider for your distro (table at top).
- **Black video / no picture** — `libmpv2`/`mpv-libs` present? Try running
  `retro_tv` from a terminal and look for `flutter: SEVERE` messages.
- **Missing GPU rendering on old hardware** — mpv falls back to software
  decoding; ensure your distribution's VA-API/VDPAU drivers exist.

## Notes on this distribution setup

- amd64 only. Versions below 1.2.1 shipped only Windows-branded packaging.
- The APT and DNF repositories are regenerated and re-signed on every `v*`
  tag via `.github/workflows/linux-release.yml` and published to GitHub Pages.
- Flatpak bundles are built in CI from the same `.deb` binaries; Snap and
  Arch/AUR are provided as recipes and are not auto-published (see
  `snap/snapcraft.yaml` and `packaging/arch/PKGBUILD`).