#!/bin/bash
# Headless checks for the AppKit layer. Never puts anything on screen, so it is
# safe to run while you are working. See headless-test.swift.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Only objects for sources that still exist, so a renamed file cannot leave a
# stale duplicate behind.
swift build -c release --product blink >/dev/null

# Top-level code is only allowed in a file called main.swift.
STAGE=.build/headless
mkdir -p "$STAGE"
cp packaging/macos/headless-test.swift "$STAGE/main.swift"

OUT=.build/blink-headless-test
swiftc -O \
    -I .build/release/Modules \
    $(for f in src/BlinkCore/*.swift; do echo ".build/release/BlinkCore.build/$(basename "$f").o"; done) \
    $(ls src/BlinkMac/*.swift | grep -v 'App.swift') \
    "$STAGE/main.swift" \
    -o "$OUT"
"$OUT"
