#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/package-cache" --scratch-path "$PWD/.build-preview" -Xswiftc -DQUILL_PREVIEW
python3 scripts/package-app.py .build-preview --preview
