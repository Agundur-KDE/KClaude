#!/bin/bash
# SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
set -e

rm -f ~/.local/bin/kclauderunner
rm -f ~/.local/share/krunner/dbusplugins/de.agundur.kclauderunner.desktop
rm -f ~/.local/share/dbus-1/services/de.agundur.kclauderunner.service

if pgrep -x krunner > /dev/null; then
    kquitapp6 krunner 2>/dev/null || killall krunner
fi

echo "KClaude KRunner plugin removed."
