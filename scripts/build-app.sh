#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Workarounds for Command Line Tools 27.0 without Xcode; see "Command Line Tools 27.0" in CONTRIBUTING.md.
BUILD_SYSTEM=
DEVELOPER=${DEVELOPER_DIR:-$(xcode-select -p)}
case "$DEVELOPER" in */CommandLineTools)
    # The macOS 27 SDK makes SwiftUI's @State a macro, but only Xcode ships its SwiftUIMacros plugin.
    if [ -z "${SDKROOT:-}" ] && [ ! -e "$DEVELOPER/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
        for sdk in $(printf '%s\n' "$DEVELOPER"/SDKs/MacOSX[0-9]*.sdk | sort -rV); do
            [ -f "$sdk/SDKSettings.plist" ] || continue
            grep -rqs 'type: "StateMacro"' "$sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/" && continue
            echo "note: building against $sdk; the newer default SDK needs Xcode's SwiftUI macros." >&2
            export SDKROOT="$sdk"
            break
        done
    fi
    # Swift Build won't start if any SDK folder lacks SDKSettings.plist, so use the deprecated native build system instead.
    for sdk in "$DEVELOPER"/SDKs/*.sdk; do
        [ -f "$sdk/SDKSettings.plist" ] && continue
        echo "warning: $sdk is an incomplete leftover SDK that breaks Swift Build; falling back to --build-system native." >&2
        echo "warning: remove it with: sudo rm -rf '$sdk'" >&2
        BUILD_SYSTEM="--build-system native"
        break
    done
esac
if [ "${UNIVERSAL_BUILD:-0}" = 1 ]; then
    swift build -c release --disable-sandbox $BUILD_SYSTEM --cache-path "$PWD/.build/package-cache" --arch arm64 --arch x86_64
    QUILL_BINARY_DIR=$(swift build -c release --disable-sandbox $BUILD_SYSTEM --show-bin-path --arch arm64 --arch x86_64)
else
    swift build -c release --disable-sandbox $BUILD_SYSTEM --cache-path "$PWD/.build/package-cache"
    QUILL_BINARY_DIR=$(swift build -c release --disable-sandbox $BUILD_SYSTEM --show-bin-path)
fi
export QUILL_BINARY_DIR
python3 scripts/package-app.py .build
