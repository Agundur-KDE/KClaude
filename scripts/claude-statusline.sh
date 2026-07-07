#!/usr/bin/env bash
# Claude Code statusLine hook: side-channel that writes context-window usage
# into ~/.config/kclaude/status.json (read by the KClaude plasmoid for the
# per-session token indicator), then passes through to whatever statusLine
# command was configured before KClaude wired itself in, so the visible
# terminal prompt itself doesn't change.
set -euo pipefail

status_file="$HOME/.config/kclaude/status.json"
lock_file="$status_file.lock"
input="$(cat)"

session_id="$(jq -r '.session_id // empty' <<<"$input")"
used_pct="$(jq -r '.context_window.used_percentage // empty' <<<"$input")"
window_size="$(jq -r '.context_window.context_window_size // 200000' <<<"$input")"

if [[ -n "$session_id" && -n "$used_pct" ]]; then
    mkdir -p "$(dirname "$status_file")"
    [[ -f "$status_file" ]] || echo '{}' >"$status_file"

    exec 9>"$lock_file"
    flock 9
    tmp="$(mktemp)"
    jq --arg sid "$session_id" --argjson pct "$used_pct" --argjson win "$window_size" \
        '.[$sid] = ((.[$sid] // {state: "running"}) + {used_percentage: $pct, context_window_size: $win, updated_at: (now | floor)})' \
        "$status_file" >"$tmp"
    cat "$tmp" >"$status_file"
    rm -f "$tmp"
fi

# ponytail: version dir in the ponytail plugin path changes on updates, glob for it.
ponytail_script="$(ls -d "$HOME"/.claude/plugins/cache/ponytail/ponytail/*/hooks/ponytail-statusline.sh 2>/dev/null | sort -V | tail -1)"
if [[ -n "$ponytail_script" ]]; then
    bash "$ponytail_script"
fi
