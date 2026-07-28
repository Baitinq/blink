#!/bin/bash
# Builds and installs the Linux port for the current user.
#   deps (Debian/Ubuntu): libx11-dev libxss-dev libxrandr-dev libcairo2-dev pkg-config
#   deps (Fedora):        libX11-devel libXScrnSaver-devel libXrandr-devel cairo-devel
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release blink-selftest
swift build -c release --product blink

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.config/autostart"
install -m 755 .build/release/blink "$HOME/.local/bin/blink"
install -m 644 packaging/blink.service "$HOME/.config/systemd/user/blink.service"
install -m 644 packaging/blink.desktop "$HOME/.config/autostart/blink.desktop"

if command -v systemctl >/dev/null; then
  systemctl --user daemon-reload
  systemctl --user enable --now blink
  echo "▸ started via systemd --user (systemctl --user status blink)"
else
  echo "▸ installed; autostart entry written to ~/.config/autostart"
fi
echo "▸ blink status | blink pause 1h | blink break"
