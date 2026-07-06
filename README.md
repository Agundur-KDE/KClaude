<div align="center">
  <h1>KClaude</h1>
  <p>KDE Plasma 6 panel widget for Claude Code: save sessions, resume them<br>
  in an embedded terminal, get notified in the panel when Claude asks something.</p>
</div>

## What it does

- **Session launcher.** Save a name, description, working directory and
  `claude --resume` session ID. Click a saved session and KClaude opens a real
  terminal — embedded in the plasmoid via `konsolepart` (the same KPart Kate
  uses for its built-in terminal) — already `cd`'d into the right directory,
  and types `claude --resume <id>` for you.
- **Panel notifications.** `scripts/claude-notify.sh` hooks into Claude Code's
  `Notification` event and pops up a panel notification (+ optional warning
  sound) whenever Claude is waiting on you — permission prompt, idle, or an
  MCP elicitation dialog. The sound is toggled from the plasmoid itself.

Sessions persist to `~/.config/kclaude/sessions.json`, the sound toggle to
`~/.config/kclaude/notify.json` — both plain JSON, no daemon required.

## Requirements

- Qt ≥ 6.7, KDE Frameworks ≥ 6.10 (incl. KParts), CMake ≥ 3.16, Extra CMake Modules
- `konsolepart` (ships with Konsole), `gdbus`, `paplay`, `jq` — for the notification hook

On openSUSE Tumbleweed:
```bash
sudo zypper install cmake extra-cmake-modules kf6-ki18n-devel kf6-parts-devel \
     qt6-quick-devel qt6-widgets-devel qt6-test-devel
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

## Panel notifications setup

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "bash /home/alec/projects/KClaude/scripts/claude-notify.sh" }] },
      { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "bash /home/alec/projects/KClaude/scripts/claude-notify.sh" }] },
      { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "bash /home/alec/projects/KClaude/scripts/claude-notify.sh" }] }
    ]
  }
}
```

The `Notification` hook is fire-and-forget — it can inform you, not answer the
prompt for you. Toggle the warning sound from the "Warnton bei Rückfragen"
checkbox in the plasmoid; the popup itself always shows.

## Contributing

Fork and adapt freely.
