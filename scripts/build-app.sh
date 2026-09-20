#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
if [ "${UNIVERSAL_BUILD:-0}" = 1 ]; then
    swift build -c release --disable-sandbox --cache-path "$PWD/.build/package-cache" --arch arm64 --arch x86_64
    QUILL_BINARY_DIR=$(swift build -c release --disable-sandbox --show-bin-path --arch arm64 --arch x86_64)
else
    swift build -c release --disable-sandbox --cache-path "$PWD/.build/package-cache"
    QUILL_BINARY_DIR=$(swift build -c release --disable-sandbox --show-bin-path)
fi
export QUILL_BINARY_DIR
python3 scripts/package-app.py .build
