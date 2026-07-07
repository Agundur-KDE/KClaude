<div align="center">
  <h1>KClaude</h1>
  <p>KDE Plasma 6 panel widget for Claude Code: save sessions, resume them<br>
  in a terminal, see at a glance which ones are waiting on you and how full<br>
  their context window is.</p>
</div>

## What it does

- **Session launcher.** Save a name, description, working directory and
  `claude --resume` session ID. Click a saved session and KClaude spawns
  `konsole --workdir <dir> -e claude --resume <id>` for you.
- **Live status per session.** A colored dot next to each session shows
  whether Claude is running or waiting on you, plus a `%` figure for how full
  its context window is.
- **Panel notifications.** `scripts/claude-notify.sh` hooks into Claude Code's
  `Notification` event and pops up a panel notification (+ optional warning
  sound) whenever Claude is waiting on you — permission prompt, idle, or an
  MCP elicitation dialog. The sound is toggled from the plasmoid itself.

Sessions persist to `~/.config/kclaude/sessions.json`, the sound toggle to
`~/.config/kclaude/notify.json`, live status to `~/.config/kclaude/status.json`
— all plain JSON, no daemon required.

There's no embedded terminal and no C++ process handling anymore — clicking a
session just launches a real, independent `konsole` window via Plasma's
`executable` dataengine. Simpler, and it means a notification (or a future
KRunner action) can just as well launch/focus a terminal without needing to
reach into the panel widget at all.

## Requirements

- Qt ≥ 6.7, KDE Frameworks ≥ 6.10, CMake ≥ 3.16, Extra CMake Modules
- `konsole`, `gdbus`, `paplay`, `jq` — for launching sessions and the notification/status hooks

On openSUSE Tumbleweed:
```bash
sudo zypper install cmake extra-cmake-modules kf6-ki18n-devel \
     qt6-quick-devel qt6-test-devel
```

## Build & install

```bash
git clone git@github.com:Agundur-KDE/KClaude.git
cd KClaude
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install
```

## Try it without installing

```bash
kpackagetool6 --type Plasma/Applet --install package/
QML_IMPORT_PATH=build/bin QT_QPA_PLATFORM=xcb plasmoidviewer -a de.agundur.kclaude
```

## Test

```bash
cd build
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

- `claude-statusline.sh` writes the context-window `used_percentage` into
  `status.json` on every prompt render, then passes through to whatever
  statusLine command you already had configured (so your terminal prompt
  itself doesn't change) — if you use a different statusLine tool, adjust the
  pass-through call at the bottom of the script.
- `claude-running.sh` marks a session "running" again once you submit a prompt.
- `claude-notify.sh` marks a session "waiting" (plus sound + popup) when
  Claude pauses for input.

The `Notification` hook is fire-and-forget — it can inform you, not answer the
prompt for you. Toggle the warning sound from the "Warnton bei Rückfragen"
checkbox in the plasmoid; the popup itself always shows.

## Contributing

Fork and adapt freely.
