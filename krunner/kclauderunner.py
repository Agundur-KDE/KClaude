#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Agundur <info@agundur.de>
# SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
"""KRunner D-Bus plugin: type "claude <name>" to raise/resume a saved
KClaude session. Reads the same ~/.config/kclaude/sessions.json the panel
widget writes, and reuses its exact spawn/focus shell commands (ported
here rather than shared — same "independent components" pattern already
used between geo-scanner and schema-checker in the Agundur BonsaiPress
codebase) so there is only one source of truth for what a session looks
like, even though the launch logic itself is duplicated.
"""
import json
import os
import shlex
import subprocess

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

SESSIONS_FILE = os.path.expanduser("~/.config/kclaude/sessions.json")
TRIGGER = "kc "


def load_sessions():
    try:
        with open(SESSIONS_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def has_tmux():
    return subprocess.run(
        ["sh", "-c", "command -v tmux"], capture_output=True
    ).returncode == 0


def launch(session):
    session_id = session["sessionId"]
    marker = "kclaude-" + session_id
    directory = os.path.expanduser(session.get("directory", "~"))

    cmd = "claude --resume " + shlex.quote(session_id)
    if session.get("name"):
        cmd += " --name " + shlex.quote(session["name"])
    if has_tmux():
        # -A: attach instead of erroring ("duplicate session: <marker>")
        # if a tmux session with this marker already exists but its
        # konsole window was closed — `found` below only checks for a
        # live konsole process, not a live tmux session.
        cmd = "tmux new-session -A -s " + shlex.quote(marker) + " " + cmd

    spawn = (
        "setsid -f konsole --hold -p tabtitle=" + shlex.quote(marker)
        + " --workdir " + shlex.quote(directory) + " -e " + cmd
    )

    # Same self-match pitfall as the QML launch(): pgrep -f sees this very
    # shell's own argv, so restrict to processes whose actual executable
    # is konsole.
    found = (
        "found=0; for pid in $(pgrep -f " + shlex.quote(marker) + "); do "
        '[ "$(cat /proc/$pid/comm 2>/dev/null)" = konsole ] && found=1; done; '
        '[ "$found" = 1 ]'
    )

    focus_script = "/tmp/" + marker + ".kwinscript.js"
    js = (
        "var w=workspace.windowList();for(var i=0;i<w.length;i++){"
        "if(w[i].caption&&w[i].caption.indexOf(" + json.dumps(marker) + ")!==-1){"
        "workspace.activeWindow=w[i];}}"
    )
    activate = (
        "cat > " + shlex.quote(focus_script) + " <<'EOF'\n" + js + "\nEOF\n"
        "qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript kclaude-focus\n"
        "qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "
        + shlex.quote(focus_script) + " kclaude-focus\n"
        "qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start"
    )

    subprocess.Popen(["sh", "-c", "if " + found + "; then " + activate + "; else " + spawn + "; fi"])


class KClaudeRunner(dbus.service.Object):
    def __init__(self, bus):
        dbus.service.Object.__init__(self, bus, "/kclauderunner")

    @dbus.service.method("org.kde.krunner1", in_signature="s", out_signature="a(sssida{sv})")
    def Match(self, query):
        if not query.lower().startswith(TRIGGER):
            return []
        term = query[len(TRIGGER):].strip().lower()
        matches = []
        for session in load_sessions():
            name = session.get("name", "")
            if term and term not in name.lower():
                continue
            exact = term == name.lower()
            props = {"subtext": session.get("directory", "")}
            matches.append((
                session["sessionId"], name, "utilities-terminal",
                100 if exact else 30, 1.0 if exact else 0.7, props,
            ))
        return matches

    @dbus.service.method("org.kde.krunner1", in_signature="ss")
    def Run(self, matchId, actionId):
        for session in load_sessions():
            if session["sessionId"] == matchId:
                launch(session)
                return


if __name__ == "__main__":
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    bus_name = dbus.service.BusName("de.agundur.kclauderunner", bus)
    KClaudeRunner(bus)
    GLib.MainLoop().run()
