%ifarch aarch64
%undefine source_date_epoch_from_changelog
%endif

Name:           kclaude
Version:        0.3.2
Release:        1%{?dist}
Summary:        KDE Plasma 6 panel widget for Claude Code sessions

License:        GPL-2.0-or-later OR GPL-3.0-or-later
URL:            https://github.com/Agundur-KDE/KClaude


BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  gettext
BuildRequires:  qt6-base-devel
BuildRequires:  qt6-declarative-devel
BuildRequires:  kf6-extra-cmake-modules
BuildRequires:  kf6-ki18n-devel


Requires:       plasma6-workspace
Recommends:     konsole
Recommends:     spectacle

%description
KClaude is a KDE Plasma 6 panel widget for Claude Code: save sessions,
resume them in a terminal, see at a glance which ones are waiting on you,
and check your Claude.ai Pro/Max rate-limit quota — all from the panel.

Source0: _service

%prep

rm -rf ./*

shopt -s nullglob
picked=""
for d in %{_sourcedir}/KClaude-* %{_sourcedir}/kclaude-* %{_sourcedir}/KClaude ; do
  if [ -d "$d" ] && [ -f "$d/CMakeLists.txt" ]; then
    picked="$d"
    break
  fi
done

if [ -n "$picked" ]; then
  cp -a "$picked"/. .
else
  for f in %{_sourcedir}/* ; do
    base="$(basename "$f")"
    case "$base" in
      *.spec|*.dsc|*.changes|*.obsinfo|_service|service_attic|screenshot|*.patch)
        continue ;;
    esac
    cp -a "$f" .
  done
fi

%build
%cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=%{_prefix}
%cmake_build

%install
%cmake_install


%files
%doc README.md
%dir %{_datadir}/plasma/plasmoids/de.agundur.kclaude
%dir %{_datadir}/plasma/plasmoids/de.agundur.kclaude/contents
%dir %{_datadir}/plasma/plasmoids/de.agundur.kclaude/contents/ui
%{_datadir}/plasma/plasmoids/de.agundur.kclaude/metadata.json
%{_datadir}/plasma/plasmoids/de.agundur.kclaude/contents/ui/main.qml
%{_datadir}/plasma/plasmoids/de.agundur.kclaude/contents/ui/FullRepresentation.qml
%{_datadir}/plasma/plasmoids/de.agundur.kclaude/contents/ui/ShellQuote.js
%{_datadir}/icons/hicolor/*/apps/kclaude.png
%{_datadir}/locale/*/LC_MESSAGES/plasma_applet_de.agundur.kclaude.mo

%changelog
* Fri Jul 10 2026 Alec <info@agundur.de> - 0.3.2
- Fixed "Neue Sitzung": konsole closed immediately when you typed exit in
  Claude, so the --resume session ID it prints on exit was never visible
  to copy. Added --hold so the terminal stays open after the session ends.
- Fixed Version field being stuck at 0.1 in this spec despite %changelog
  already listing 0.3.1 — OBS builds were shipping the wrong version.

* Thu Jul 09 2026 Alec <info@agundur.de> - 0.3.1
- Session retention: reads Claude Code's cleanupPeriodDays (read-only,
  never written — shared with every other running Claude Code window)
  and dims a saved session whose local transcript is already gone, with
  an explanatory tooltip
- Fixed saved sessions silently keeping a trailing newline when pasted
  into the name/directory/session-ID fields

* Tue Jul 07 2026 Alec <info@agundur.de> - 0.1
- Initial OBS package
