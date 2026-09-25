#!/bin/sh
# Rebuild platform icon assets on macOS; ordinary app builds use committed assets.
set -eu
cd "$(dirname "$0")/.."
icon_set=build/ClockAndLedger.iconset
mkdir -p "$icon_set"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" Resources/Artwork/ClockAndLedger-master.png \
    --out "$icon_set/icon_${icon_size}x${icon_size}.png" >/dev/null
  icon_double=$((icon_size * 2))
  sips -z "$icon_double" "$icon_double" Resources/Artwork/ClockAndLedger-master.png \
    --out "$icon_set/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_set" -o Resources/ClockAndLedger.icns
sips -z 128 128 Resources/Artwork/ClockAndLedger-master.png \
  --out Resources/ClockAndLedger.png >/dev/null
