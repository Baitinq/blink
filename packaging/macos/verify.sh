#!/bin/bash
# Live end-to-end check of the built app: fast cycle, real overlay windows.
#
# Two safeguards, both learned the hard way:
#   - a scratch defaults domain, so your real settings are never rewritten
#   - a cleanup trap, so this never leaves a second engine running
set -euo pipefail
cd "$(dirname "$0")/../.."

APP=".build/Blink.app/Contents/MacOS/Blink"
SUITE="com.manuelpalenzuela.blink.verify"
test -x "$APP" || { echo "build first: packaging/macos/build.sh"; exit 1; }

COUNTER=.build/blink-windowcount
swiftc -O packaging/macos/windowcount.swift -o "$COUNTER"

defaults delete "$SUITE" 2>/dev/null || true
defaults write "$SUITE" workIntervalMinutes -int 1
defaults write "$SUITE" breakDurationSeconds -int 20
defaults write "$SUITE" warningLeadSeconds -int 5
defaults write "$SUITE" idleResetEnabled -bool false

pkill -x Blink || true
sleep 1

cleanup() {
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    defaults delete "$SUITE" 2>/dev/null || true
    echo "▸ Blink instances left running: $(pgrep -x Blink | wc -l | tr -d ' ')"
}

BLINK_DEFAULTS_SUITE="$SUITE" "$APP" &
APP_PID=$!
trap cleanup EXIT INT TERM
sleep 1

echo "▸ single-instance guard"
BLINK_DEFAULTS_SUITE="$SUITE" "$APP" 2>&1 | grep -q "already running" \
    && echo "  second copy refused to start" \
    || { echo "  FAIL: a second instance started"; exit 1; }

echo "▸ watching for a break (interval 1 min, duration 20s)"
START=$(date +%s)
STATE=0
BREAK_START=0
while [ $(( $(date +%s) - START )) -lt 150 ]; do
    OVERLAYS=$("$COUNTER")
    NOW=$(( $(date +%s) - START ))
    if [ "$STATE" = 0 ] && [ "$OVERLAYS" -gt 0 ]; then
        echo "  t=${NOW}s break started on $OVERLAYS display(s)"
        BREAK_START=$NOW
        STATE=1
    elif [ "$STATE" = 1 ] && [ "$OVERLAYS" = 0 ]; then
        LENGTH=$(( NOW - BREAK_START ))
        echo "  t=${NOW}s break ended — lasted ~${LENGTH}s (expected 20)"
        if [ "$LENGTH" -ge 19 ] && [ "$LENGTH" -le 22 ]; then
            echo "▸ PASS"
            exit 0
        fi
        echo "▸ FAIL: expected ~20s"
        exit 1
    fi
    sleep 1
done
echo "▸ FAIL: no break observed within 150s"
exit 1
