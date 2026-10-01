%global debug_package %{nil}
%global _debugsource_template %%{nil}
%global _debuginfo_template %%{nil}

# Binary-pack spec: Source0 is the Flutter Linux release bundle produced on the
# CI Linux runner (build/linux/x64/release/bundle, tarballed with top dir
# renamed to "bundle"). No flutter toolchain is needed on the build host.
Name:           retro-tv
Version:        1.2.2
Release:        6%{?dist}
Summary:        Retro-styled IPTV / YouTube streaming TV app
License:        MIT
URL:            https://mzainulabideendev.github.io/Retro-TV/
Source0:        retro-tv-linux-bundle.tar.gz
BuildArch:      x86_64
Requires:       gtk3
Requires:       mpv-libs
Requires:       libstdc++

%description
Retro TV is a Flutter desktop application that renders a nostalgic CRT
television look while playing YouTube live channels and IPTV-style streams.
It plays video directly through the native media stack (mpv/libmpv) without
relying on a web widget.

%prep
%setup -q -n bundle

%install
rm -rf %{buildroot}
install -d %{buildroot}%{_libdir}/retro-tv
install -d %{buildroot}%{_bindir}
install -d %{buildroot}%{_datadir}/applications
install -d %{buildroot}%{_datadir}/icons/hicolor/192x192/apps
install -d %{buildroot}%{_datadir}/metainfo
install -d %{buildroot}%{_datadir}/licenses/retro-tv

cp -r lib %{buildroot}%{_libdir}/retro-tv/
cp -r data %{buildroot}%{_libdir}/retro-tv/
install -m755 retro_tv %{buildroot}%{_libdir}/retro-tv/retro_tv
ln -s %{_libdir}/retro-tv/retro_tv %{buildroot}%{_bindir}/retro_tv

install -m644 %{_sourcedir}/com.retrotv.retro_tv.desktop %{buildroot}%{_datadir}/applications/com.retrotv.retro_tv.desktop
install -m644 %{_sourcedir}/app_icon.png %{buildroot}%{_datadir}/icons/hicolor/192x192/apps/retro-tv.png
install -m644 %{_sourcedir}/com.retrotv.retro_tv.metainfo.xml %{buildroot}%{_datadir}/metainfo/com.retrotv.retro_tv.metainfo.xml
install -m644 %{_sourcedir}/LICENSE %{buildroot}%{_datadir}/licenses/retro-tv/LICENSE

%files
%{_bindir}/retro_tv
%{_libdir}/retro-tv/
%{_datadir}/applications/com.retrotv.retro_tv.desktop
%{_datadir}/icons/hicolor/192x192/apps/retro-tv.png
%{_datadir}/metainfo/com.retrotv.retro_tv.metainfo.xml
%license %{_datadir}/licenses/retro-tv/LICENSE

%changelog
* Thu Oct 01 2026 mzainulabideendev <mzainulabideendev@users.noreply.github.com> - 1.2.2-6
- Release 1.2.2
* Tue Sep 29 2026 mzainulabideendev <mzainulabideendev@users.noreply.github.com> - 1.2.1-5
- Initial Linux packaging (amd64).