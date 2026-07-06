#!/usr/bin/env bash
# Claude Code Notification hook: warning sound + panel popup when Claude asks
# a question (permission prompt, idle, MCP elicitation). Wire up in
# ~/.claude/settings.json — see README.md "Notifications" section.
#
# Sound toggle lives in ~/.config/kclaude/notify.json ({"sound": true|false}),
# editable from the KClaude plasmoid itself.
set -euo pipefail

config="$HOME/.config/kclaude/notify.json"
input="$(cat)"

title="$(jq -r '.title // "Claude Code"' <<<"$input")"
message="$(jq -r '.message // "Claude braucht deine Eingabe"' <<<"$input")"

sound_enabled=true
if [[ -f "$config" ]]; then
    sound_enabled="$(jq -r '.sound // true' "$config")"
fi

if [[ "$sound_enabled" == "true" ]]; then
    paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga &
fi

# kdialog --passivepopup always shows "kdialog" as the sender — going straight to
# the Notifications D-Bus API lets us set app_name to something recognizable.
gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify \
    "KClaude" 0 "utilities-terminal" "$title" "$message" "[]" "{}" 8000 >/dev/null
