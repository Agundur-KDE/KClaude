# KClaude Runner

KRunner plugin: type `kc <name>` (Alt+Space) to raise or resume a saved
[KClaude](https://github.com/Agundur-KDE/KClaude) session by name, without
opening the panel widget first.

Pure Python D-Bus runner (`org.kde.krunner1`), no compiling, no root needed —
installs entirely to `~/.local/`. Requires `python3-dbus` and PyGObject
(both commonly preinstalled on KDE systems) and the
[KClaude](https://github.com/Agundur-KDE/KClaude) panel widget, since it reads
the same `~/.config/kclaude/sessions.json` the panel writes.

## Install / Uninstall

Run `install.sh` / `uninstall.sh` from this directory. No `sudo` required.

## Source

Part of the [KClaude](https://github.com/Agundur-KDE/KClaude) repository
(`krunner/` subdirectory) — GPL-2.0-only OR GPL-3.0-only.
