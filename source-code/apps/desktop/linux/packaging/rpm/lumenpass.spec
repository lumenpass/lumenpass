%global app_id     tranit.lumenpass.linux
%global appname    lumenpass
%global instdir    /opt/%{appname}

# Flutter ships its own pre-stripped engine library and embeds an
# absolute build path in the RUNPATH of plugin shared libraries. The
# real lookup at runtime uses the binary's $ORIGIN-relative RPATH under
# /opt/lumenpass/lib, so debug-extraction would only spam the build log
# with warnings.
%global debug_package %{nil}
%global __strip       /bin/true
%global __os_install_post %{nil}

# Quiet rpmbuild over the bundled Flutter runtime in /opt. Excluding the
# whole /opt/lumenpass/lib/ tree from auto-Provides and auto-Requires is
# the canonical pattern for self-contained third-party bundles: it
# prevents rpm from emitting spurious Requires for plugin sonames that
# only exist inside our own bundle (libtray_manager_plugin.so,
# liburl_launcher_linux_plugin.so, libsqlite3.so, libapp.so,
# libflutter_linux_gtk.so, etc.). Without these, `dnf install` would
# refuse the package even though everything resolves at runtime via the
# binary's $ORIGIN-relative RPATH.
%global __provides_exclude_from ^%{instdir}/.*$
%global __requires_exclude_from ^%{instdir}/.*$
%global __provides_exclude ^lib(flutter_linux_gtk|app|desktop_drop_plugin|flutter_secure_storage_linux_plugin|tray_manager_plugin|url_launcher_linux_plugin|sqlite3)\\.so.*$
%global __requires_exclude ^lib(flutter_linux_gtk|app|desktop_drop_plugin|flutter_secure_storage_linux_plugin|tray_manager_plugin|url_launcher_linux_plugin|sqlite3)\\.so.*$

Name:           %{appname}
Version:        %{?_lumenpass_version}%{!?_lumenpass_version:1.0.3}
Release:        1%{?dist}
Summary:        KeePass-compatible password manager

License:        MPL-2.0
URL:            https://lumenpass.app
# Source0 is provided out-of-band by build-rpm.sh, which stages the
# Flutter Linux bundle and packaging assets into a tarball at SOURCES/.
Source0:        %{appname}-%{version}.tar.gz

BuildArch:      x86_64

# Runtime dependencies (Fedora package names). Auto-detection of
# Requires for the bundled plugins is disabled above; system libraries
# linked against by /opt/lumenpass/lumenpass itself (gtk3, libsecret,
# openssl, ayatana-appindicator) are listed explicitly here.
Requires:       gtk3
Requires:       libsecret
Requires:       jsoncpp
Requires:       openssl-libs
Requires:       libayatana-appindicator-gtk3

# Build-time tooling (kept minimal; the Flutter compile happens before
# rpmbuild and we only repackage the output).
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

%description
LumenPass is a modern password manager that reads and writes
KeePass KDBX 3 and KDBX 4 vaults. It provides a 1Password-style user
interface for managing logins, passkeys, TOTP codes, SSH keys,
identities, secure notes, payment cards and bank accounts.

Features:
  * KDBX 3 and KDBX 4 read and write support via the official AuthPass
    kdbx library.
  * Native system tray integration, biometric unlock, and OS keyring
    backing.
  * Built-in TOTP authenticator and password generator with audit
    reports.
  * Optional cloud sync (Google Drive, Dropbox) and browser-extension
    bridge.
  * Cross-platform: shares a common codebase with the macOS and Windows
    desktop releases.

%prep
%setup -q -n %{appname}-%{version}

%build
# Nothing to compile here. build-rpm.sh runs `flutter build linux` on the
# host and the produced bundle is shipped inside Source0.

%install
rm -rf %{buildroot}

# Application bundle (mirrors the .deb layout under /opt).
install -d %{buildroot}%{instdir}
cp -a bundle/. %{buildroot}%{instdir}/
chmod 0755 %{buildroot}%{instdir}/%{appname}

# /usr/bin wrapper.
install -d %{buildroot}%{_bindir}
install -m 0755 assets/%{appname} %{buildroot}%{_bindir}/%{appname}

# Desktop entry + AppStream metadata.
install -d %{buildroot}%{_datadir}/applications
install -m 0644 assets/%{appname}.desktop \
  %{buildroot}%{_datadir}/applications/%{appname}.desktop
install -d %{buildroot}%{_datadir}/metainfo
install -m 0644 assets/%{appname}.metainfo.xml \
  %{buildroot}%{_datadir}/metainfo/%{appname}.metainfo.xml

# Hicolor icons.
for size in 16 32 48 64 128 256 512; do
  install -d %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps
  install -m 0644 assets/icons/${size}x${size}/%{appname}.png \
    %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/%{appname}.png
done

%check
desktop-file-validate \
  %{buildroot}%{_datadir}/applications/%{appname}.desktop
appstream-util validate-relax --nonet \
  %{buildroot}%{_datadir}/metainfo/%{appname}.metainfo.xml || true

%files
%license LICENSE
%dir %{instdir}
%{instdir}/%{appname}
%{instdir}/data
%{instdir}/lib
%{_bindir}/%{appname}
%{_datadir}/applications/%{appname}.desktop
%{_datadir}/metainfo/%{appname}.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/%{appname}.png

%post
if [ -x /usr/bin/update-desktop-database ]; then
    /usr/bin/update-desktop-database -q %{_datadir}/applications || :
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache -f -t %{_datadir}/icons/hicolor || :
fi
if [ -x /usr/bin/appstreamcli ]; then
    /usr/bin/appstreamcli refresh-cache --force >/dev/null 2>&1 || :
fi

%postun
if [ "$1" -eq 0 ]; then
    if [ -x /usr/bin/update-desktop-database ]; then
        /usr/bin/update-desktop-database -q %{_datadir}/applications || :
    fi
    if [ -x /usr/bin/gtk-update-icon-cache ]; then
        /usr/bin/gtk-update-icon-cache -f -t %{_datadir}/icons/hicolor || :
    fi
fi

%changelog
* Fri May 22 2026 TranTech Studio <admin@lumenpass.app> - 1.0.3-1
- Initial Fedora/RHEL/openSUSE RPM packaging for LumenPass.
- Mirrors the Debian package layout under /opt/lumenpass.
