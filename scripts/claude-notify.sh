#!/usr/bin/env bash
# Claude Code Notification hook: warning sound + panel popup when Claude asks
# a question (permission prompt, idle, MCP elicitation). Wire up in
# ~/.claude/settings.json — see README.md "Notifications" section.
#
# Sound toggle lives in ~/.config/kclaude/notify.json ({"sound": true|false}),
# editable from the KClaude plasmoid itself.
set -euo pipefail

config="$HOME/.config/kclaude/notify.json"
status_file="$HOME/.config/kclaude/status.json"
lock_file="$status_file.lock"
input="$(cat)"

title="$(jq -r '.title // "Claude Code"' <<<"$input")"
message="$(jq -r '.message // "Claude braucht deine Eingabe"' <<<"$input")"
session_id="$(jq -r '.session_id // empty' <<<"$input")"

if [[ -n "$session_id" ]]; then
    mkdir -p "$(dirname "$status_file")"
    [[ -f "$status_file" ]] || echo '{}' >"$status_file"

    exec 9>"$lock_file"
    flock 9
    tmp="$(mktemp "${status_file}.XXXXXX")"
    jq --arg sid "$session_id" '.[$sid] = ((.[$sid] // {}) + {state: "waiting"})' "$status_file" >"$tmp"
    mv "$tmp" "$status_file"
fi

sound_enabled=true
if [[ -f "$config" ]]; then
    sound_enabled="$(jq -r '.sound // true' "$config")"
fi

if [[ "$sound_enabled" == "true" ]]; then
    paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga &
fi

# Skip the OS popup if the KClaude panel is already open — the waiting
# session's row flashes red there instead, a second popup would be noise.
popup_state="$HOME/.config/kclaude/popup_state.json"
already_open=false
if [[ -f "$popup_state" ]]; then
    already_open="$(jq -r '.expanded // false' "$popup_state")"
fi

if [[ "$already_open" != "true" ]]; then
    # kdialog --passivepopup always shows "kdialog" as the sender — going straight to
    # the Notifications D-Bus API lets us set app_name to something recognizable.
    gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "KClaude" 0 "kclaude" "$title" "$message" "[]" "{}" 8000 >/dev/null
fi
