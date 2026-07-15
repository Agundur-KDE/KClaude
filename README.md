<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="icons/256-apps-kclaude.png">
    <img src="screenshots/logo.png" width="128" alt="KClaude logo">
  </picture>
  <h1>KClaude</h1>
  <p>Resume your Claude Code sessions without hunting for the right<br>
  directory or session ID — one click from the panel.</p>
  <p><a href="https://www.agundur.de/projects/kclaude.html">Project page</a></p>
</div>

<p align="center">
  <img src="screenshots/sessions.png" width="45%" alt="Session list with live status and rate-limit quota">
  <img src="screenshots/add-session.png" width="45%" alt="Add-session form">
</p>

## What it does

- **Session launcher.** Save a name, description, working directory and
  `claude --resume` session ID. Click a saved session and KClaude spawns
  `konsole --workdir <dir> -e claude --resume <id>` for you.
- **New session button.** Starts a fresh `claude` (no `--resume`) in a
  configurable default directory — set it once via the ⚙ Settings icon.
  `~` in the path expands to your home directory.
- **Live status per session.** A colored dot next to each session shows
  whether Claude is running or waiting on you.
- **Panel notifications.** `scripts/claude-notify.sh` hooks into Claude Code's
  `Notification` event and pops up a panel notification (+ optional warning
  sound) whenever Claude is waiting on you — permission prompt, idle, or an
  MCP elicitation dialog. The sound is toggled from the plasmoid itself.
- **Region screenshot button.** Runs `spectacle -r -b -n -c` — drag a
  rectangle, image lands straight in the clipboard, no save/copy dialogs.
  Handy for pasting something into a Claude Code session.
- **Rate-limit quota.** A small line under the toolbar shows your
  account-wide 5h/7d usage window (`used_percentage` + local reset time) —
  Claude.ai Pro/Max only. Not per-session, not rings/bars, just two numbers
  and two times. See "Rate-limit quota" below for how it's wired up.
- **Expired-session greying.** A saved session whose local transcript
  Claude Code has already deleted shows dimmed with a tooltip explaining
  why — `--resume` would silently start a fresh conversation instead of
  actually resuming. See "Session retention" below.
- **Cookie button.** 🍪 sends a real keystroke into whichever session KClaude
  last launched or focused, and raises its window first. Needs `tmux`
  (optional, see Requirements) — greys out without it. See "Cookie button"
  below.

Sessions persist to `~/.config/kclaude/sessions.json`, the sound toggle to
`~/.config/kclaude/notify.json`, live status to `~/.config/kclaude/status.json`,
quota to `~/.config/kclaude/quota.json` — all plain JSON, no daemon required.

There's no embedded terminal and no C++ process handling anymore — clicking a
session just launches a real, independent `konsole` window via Plasma's
`executable` dataengine. Simpler, and it means a notification (or a future
KRunner action) can just as well launch/focus a terminal without needing to
reach into the panel widget at all.

## Requirements

Pure QML, no compiled plugin — Qt ≥ 6.7 and KDE Frameworks ≥ 6.10 (whatever
your Plasma 6 install already has) is all you need at runtime.
`konsole`, `gdbus`, `paplay`, `jq`, `spectacle` — for launching sessions and
the notification/status hooks. `tmux` (optional) — only for the 🍪 button,
everything else works fine without it.

UI is translated into German, Spanish and French (falls back to English
otherwise) — see `translate/`.

## Install

Easiest: **"Get New Widgets"** in System Settings, or grab the `.plasmoid`
from the [latest release](https://github.com/Agundur-KDE/KClaude/releases/latest)
and:
```bash
kpackagetool6 --type Plasma/Applet --install kclaude-*.plasmoid
```

Also available as a proper package, if you'd rather have `zypper`/`apt`
manage updates:
```bash
# openSUSE Tumbleweed
sudo zypper ar -f https://download.opensuse.org/repositories/home:/Agundur/openSUSE_Tumbleweed/home:Agundur.repo
sudo zypper --gpg-auto-import-keys ref
sudo zypper in kclaude

# Debian/Ubuntu — grab the .deb from the latest release above
```

Or straight from source, no build step needed either:
```bash
git clone git@github.com:Agundur-KDE/KClaude.git
kpackagetool6 --type Plasma/Applet --install KClaude/package/
```

## Development: running the test suite

Only needed if you're contributing — regular use needs no build step at all.
```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make tst_plasmoid
ctest --output-on-failure
```

## Notifications & live status setup

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /home/alec/projects/KClaude/scripts/claude-statusline.sh"
  },
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "bash /home/alec/projects/KClaude/scripts/claude-running.sh" }] }
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "bash /home/alec/projects/KClaude/scripts/claude-notify.sh" }] },
      { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "bash /home/alec/projects/KClaude/scripts/claude-notify.sh" }] },
      { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "bash /home/alec/projects/KClaude/scripts/claude-notify.sh" }] }
    ]
  }
}
```

- `claude-running.sh` marks a session "running" again once you submit a prompt.
- `claude-notify.sh` marks a session "waiting" (plus sound + popup) when
  Claude pauses for input.
- `claude-statusline.sh` writes `rate_limits.five_hour`/`seven_day` from the
  statusLine hook JSON into `quota.json`, then passes through to whatever
  statusLine command you already had configured (so your terminal prompt
  itself doesn't change) — if you use a different statusLine tool, adjust the
  pass-through call at the bottom of the script.

The `Notification` hook is fire-and-forget — it can inform you, not answer the
prompt for you. Toggle the warning sound from the "Warning sound on prompts"
checkbox in the plasmoid; the popup itself always shows. Note `idle_prompt`
can fire during any longer pause, not just when Claude is genuinely blocked —
drop that matcher if it's too noisy.

## Rate-limit quota

This is Anthropic's account-wide 5h/7d rate-limit window (Claude.ai Pro/Max
only) — a different thing from the per-session context window. It comes
straight from the statusLine hook's `rate_limits` field, no OAuth handling or
API calls of our own needed.

## Session retention

Claude Code keeps a session's local transcript (what `--resume` actually
reads) for `cleanupPeriodDays` days — 30 by default — then deletes it
automatically on its next startup, independent of anything KClaude does.
The saved shortcut in KClaude's own `sessions.json` never expires on its
own (delete it yourself via the 🗑 button), so without this feature a
session could look perfectly fine in the list while `--resume` quietly
starts a brand new conversation because the transcript is already gone.

KClaude reads (never writes) `cleanupPeriodDays` from Claude Code's own
`~/.claude/settings.json` — shown read-only in ⚙ Settings, since that file
is shared with every other running Claude Code window and writing to it
risks a lost-update race. For each saved session it checks whether
`~/.claude/projects/<encoded-dir>/<session-id>.jsonl` still exists — more
accurate than estimating from a saved date — and dims the entry with an
explanatory tooltip if it's gone. Want longer retention? Set
`cleanupPeriodDays` yourself in `~/.claude/settings.json`.

## Cookie button

🍪 sends a real keystroke — literally `🍪` + Enter — into whichever session
KClaude most recently launched or focused, via `tmux send-keys`. It's not a
notification; if the session is `tmux`-wrapped (see Requirements), the text
lands straight in Claude's actual input, same as if you'd typed it yourself.

Why `tmux` and not `xdotool`/`ydotool`: `xdotool` doesn't reliably reach
native Wayland windows, and `ydotool` needs a systemwide `ydotoold` daemon
with `/dev/uinput` access — global keystroke injection, more than a joke
button warrants. `tmux send-keys` writes straight into the pty it owns, no
X11/Wayland dependency, no elevated permissions.

Requires `tmux` to be installed, and the session to have been (re)started
after KClaude detected it — sessions launched before `tmux` was installed
won't be wrapped until you relaunch them. No `tmux`? The button just greys
out with a tooltip; everything else about KClaude works exactly as before.

Please don't overfeed your Claude. One cookie is a thank-you; fifty in a row
is a denial-of-service attack on its patience.

## KRunner plugin

Optional, separate from the panel widget: type `kc <name>` in KRunner
(Alt+Space) to raise or resume a saved session by name, without opening the
panel first. Fuzzy-matches against the same `~/.config/kclaude/sessions.json`
the panel writes, and reuses the same spawn/focus/tmux logic as clicking a
session in the panel.

It's a standalone D-Bus runner (`krunner/kclauderunner.py`, `org.kde.krunner1`
interface) — not bundled into the plasmoid's `.plasmoid`/RPM/`.deb` install
yet, so it needs a manual install for now:

```bash
mkdir -p ~/.local/share/krunner/dbusplugins ~/.local/share/dbus-1/services
cp krunner/de.agundur.kclauderunner.desktop ~/.local/share/krunner/dbusplugins/
cat > ~/.local/share/dbus-1/services/de.agundur.kclauderunner.service <<EOF
[D-BUS Service]
Name=de.agundur.kclauderunner
Exec=/usr/bin/python3 $(pwd)/krunner/kclauderunner.py
EOF
kquitapp6 krunner   # picks up the new plugin on its next auto-start
```

Needs `python3-dbus` (`dbus-python`) and PyGObject — both commonly
preinstalled on KDE systems, since Plasma itself depends on them.

## Contributing

Fork and adapt freely.
