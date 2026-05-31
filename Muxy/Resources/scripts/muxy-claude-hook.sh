#!/usr/bin/env bash
set -euo pipefail

if [ -z "${MUXY_SOCKET_PATH:-}" ] || [ -z "${MUXY_PANE_ID:-}" ]; then
    exit 0
fi

event="${1:-}"
input=$(cat)

send_notification() {
    local type="$1"
    local title="$2"
    local body="$3"
    printf '%s|%s|%s|%s\n' "$type" "$MUXY_PANE_ID" "$title" "$body" \
        | nc -U -N "$MUXY_SOCKET_PATH" 2>/dev/null || true
}

extract_transcript_tail() {
    local tpath
    tpath=$(printf '%s' "$input" | grep -o '"transcript_path":"[^"]*"' | head -1 | cut -d'"' -f4)
    [ -n "$tpath" ] && [ -f "$tpath" ] || return
    grep -o '"text":"[^"]*"' "$tpath" 2>/dev/null | tail -1 | cut -d'"' -f4 | tr '|' ' ' | head -c 160
}

extract_last_message() {
    local msg=""
    msg=$(printf '%s' "$input" | grep -o '"last_assistant_message":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$msg" ]; then
        printf '%s' "$msg" | tr '|' ' ' | head -c 200
        return
    fi
    printf 'Session completed'
}

extract_message() {
    local msg=""
    msg=$(printf '%s' "$input" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$msg" ]; then
        printf '%s' "$msg" | tr '|' ' ' | head -c 200
        return
    fi
    printf 'Needs attention'
}

case "$event" in
    notification)
        reason=$(extract_message)
        context=$(extract_transcript_tail)
        if [ -n "$context" ]; then
            send_notification "claude_hook" "Claude Code" "$reason — $context"
        else
            send_notification "claude_hook" "Claude Code" "$reason"
        fi
        ;;
    stop)
        body=$(extract_last_message)
        send_notification "claude_hook" "Claude Code" "$body"
        ;;
esac
