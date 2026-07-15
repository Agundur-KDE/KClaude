#!/bin/bash
# SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
set -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p ~/.local/bin ~/.local/share/krunner/dbusplugins ~/.local/share/dbus-1/services

cp "$script_dir/kclauderunner.py" ~/.local/bin/kclauderunner
chmod +x ~/.local/bin/kclauderunner

cp "$script_dir/de.agundur.kclauderunner.desktop" ~/.local/share/krunner/dbusplugins/

cat > ~/.local/share/dbus-1/services/de.agundur.kclauderunner.service <<EOF
[D-BUS Service]
Name=de.agundur.kclauderunner
Exec=$HOME/.local/bin/kclauderunner
EOF

if pgrep -x krunner > /dev/null; then
    kquitapp6 krunner 2>/dev/null || killall krunner
fi

echo "Installation finished! Type \"kc <name>\" in KRunner (Alt+Space) to resume a saved KClaude session."
