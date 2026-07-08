#!/usr/bin/env bash
# Claude Code statusLine hook: side-channel that writes the account-wide
# rate-limit quota (5h/7d window usage + reset time — NOT the per-conversation
# context window, see README) into ~/.config/kclaude/quota.json, then passes
# through to whatever statusLine command was configured before KClaude wired
# itself in, so the visible terminal prompt itself doesn't change.
set -euo pipefail

quota_file="$HOME/.config/kclaude/quota.json"
lock_file="$quota_file.lock"
input="$(cat)"

five_hour_pct="$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")"
five_hour_reset="$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")"
seven_day_pct="$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")"
seven_day_reset="$(jq -r '.rate_limits.seven_day.resets_at // empty' <<<"$input")"

# ponytail: only Claude.ai Pro/Max sessions get rate_limits at all, and it can
# be absent on the very first render — skip the write rather than clobber.
if [[ -n "$five_hour_pct" || -n "$seven_day_pct" ]]; then
    mkdir -p "$(dirname "$quota_file")"

    exec 9>"$lock_file"
    flock 9
    tmp="$(mktemp "${quota_file}.XXXXXX")"
    jq -n \
        --argjson fp "${five_hour_pct:-null}" --argjson fr "${five_hour_reset:-null}" \
        --argjson sp "${seven_day_pct:-null}" --argjson sr "${seven_day_reset:-null}" \
        '{five_hour: {used_percentage: $fp, resets_at: $fr}, seven_day: {used_percentage: $sp, resets_at: $sr}}' \
        >"$tmp"
    mv "$tmp" "$quota_file"
fi

# ponytail: version dir in the ponytail plugin path changes on updates, glob for it.
ponytail_script="$(ls -d "$HOME"/.claude/plugins/cache/ponytail/ponytail/*/hooks/ponytail-statusline.sh 2>/dev/null | sort -V | tail -1)"
if [[ -n "$ponytail_script" ]]; then
    bash "$ponytail_script"
fi
