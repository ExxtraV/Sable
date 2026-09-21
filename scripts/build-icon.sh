#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Sable.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/sable-logo.png --out "build/Sable.iconset/icon_${size}x${size}.png" >/dev/null
    twice=$((size * 2))
    sips -z "$twice" "$twice" Assets/sable-logo.png --out "build/Sable.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/pack-icon.py
