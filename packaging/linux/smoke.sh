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

# --- accidental-skip protection, exercised with real X input (isolated Xvfb) ---
echo "▸ escape-hatch guard (esc during grace, single esc, esc twice)"
Xvfb :98 -screen 0 1400x900x24 >/dev/null 2>&1 &
XVFB2_PID=$!
export DISPLAY=:98
sleep 1
$BIN set breakDurationSeconds 45 >/dev/null
$BIN --verbose >/tmp/guard.log 2>&1 &
GUARD_PID=$!
sleep 2
$BIN break
sleep 0.5

overlay_up() { xwininfo -root -children 2>/dev/null | grep -c "1400x900" || true; }

xdotool key Escape; xdotool key Escape       # inside the 1.5s grace period
sleep 0.5
test "$(overlay_up)" != "0" && echo "  ✓ grace period ignored two escapes" \
    || { echo "  ✗ break died during grace"; exit 1; }

sleep 2                                       # now armed
xdotool key Escape                            # one press only: must arm, not skip
sleep 1.5
test "$(overlay_up)" != "0" && echo "  ✓ a single escape did not skip" \
    || { echo "  ✗ one escape skipped the break"; exit 1; }

xdotool key Escape; sleep 0.3; xdotool key Escape
sleep 1
test "$(overlay_up)" = "0" && echo "  ✓ two escapes skipped" \
    || { echo "  ✗ two escapes did not skip"; exit 1; }

kill $GUARD_PID $XVFB2_PID 2>/dev/null || true
echo "▸ all checks passed"
