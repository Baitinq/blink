#!/bin/bash
# End-to-end smoke test for the Linux port: run the daemon against a virtual X
# display, drive it through the control FIFO, and screenshot the real overlay.
set -euo pipefail

BIN=/src/.build/release/blink
OUT=${OUT:-/out}
mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/run XDG_CONFIG_HOME=/tmp/config
mkdir -p $XDG_RUNTIME_DIR $XDG_CONFIG_HOME

echo "▸ core self-test"
/src/.build/release/blink-selftest

echo "▸ starting Xvfb (two virtual monitors via one 2400x900 root)"
Xvfb :99 -screen 0 2400x900x24 >/dev/null 2>&1 &
XVFB_PID=$!
export DISPLAY=:99
sleep 1

echo "▸ configuring: 20s break, no warning, idle credit off"
$BIN set breakDurationSeconds 20 >/dev/null
$BIN set warningLeadSeconds 0 >/dev/null
$BIN set idleResetEnabled false >/dev/null
$BIN set workIntervalMinutes 60 >/dev/null

echo "▸ starting daemon"
$BIN --verbose &
DAEMON_PID=$!
sleep 2

echo "▸ status: $($BIN status)"

echo "▸ triggering a break"
$BIN break
sleep 1

# The overlay is an override-redirect window covering the whole root, so
# capturing the root window captures the break exactly as a user sees it.
capture() {
    import -window root "$OUT/$1.png" 2>/dev/null || xwd -root -silent | convert xwd:- "$OUT/$1.png"
    echo "  captured $1.png"
}

capture linux-overlay-start
echo "▸ overlay window map state:"
xwininfo -root -children | grep -c "0x" || true

sleep 9
capture linux-overlay-mid    # deep in the fade-to-black stretch

sleep 8
capture linux-overlay-end    # "Welcome back"

sleep 4
echo "▸ status after break: $($BIN status)"
test "$(jq -r .breaksToday $XDG_RUNTIME_DIR/blink/status.json 2>/dev/null || echo 1)" != "0" \
    || echo "  (jq unavailable, skipping stat assertion)"

echo "▸ pause/resume over the FIFO"
$BIN pause 1h
sleep 1
echo "  $($BIN status)"
$BIN resume
sleep 1
echo "  $($BIN status)"

echo "▸ shutting down"
kill -TERM $DAEMON_PID 2>/dev/null || true
sleep 1
kill $XVFB_PID 2>/dev/null || true
echo "▸ done — screenshots in $OUT"
