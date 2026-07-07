#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook: marks the session "running" again in
# ~/.config/kclaude/status.json — counterpart to claude-notify.sh, which
# marks it "waiting" when Claude pauses for input.
set -euo pipefail

status_file="$HOME/.config/kclaude/status.json"
lock_file="$status_file.lock"
input="$(cat)"

session_id="$(jq -r '.session_id // empty' <<<"$input")"
[[ -n "$session_id" ]] || exit 0

mkdir -p "$(dirname "$status_file")"
[[ -f "$status_file" ]] || echo '{}' >"$status_file"

exec 9>"$lock_file"
flock 9
tmp="$(mktemp)"
jq --arg sid "$session_id" '.[$sid] = ((.[$sid] // {}) + {state: "running"})' "$status_file" >"$tmp"
cat "$tmp" >"$status_file"
rm -f "$tmp"
