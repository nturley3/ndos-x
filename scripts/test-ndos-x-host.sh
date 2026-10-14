#!/bin/bash
set -euo pipefail
ndos_x_root=$(cd "$(dirname "$0")/.." && pwd)
ndos_x_simulator=${1:-booted}
ndos_x_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
ndos_x_prefix="$ndos_x_root/output/ndos-x-engine/iphonesimulator-arm64/prefix"
ndos_x_binary="$ndos_x_root/output/ndos-x-host-check"
[[ -f "$ndos_x_prefix/lib/libSDL2.a" ]] || { echo 'Build the Simulator engine first: NDOS_X_SDK=iphonesimulator bash scripts/build-ndos-x-engine.sh' >&2; exit 1; }
xcrun --sdk iphonesimulator clang++ -target arm64-apple-ios15.4-simulator -isysroot "$ndos_x_sdk" \
    -std=c++14 -fobjc-arc -DSDL_MAIN_HANDLED -I"$ndos_x_root/Experimental/Host" \
    -I"$ndos_x_root/vendor/SDL2/include" "$ndos_x_root/Experimental/Tests/host-check.mm" \
    "$ndos_x_root/Experimental/Host/NDOSXHost.mm" "$ndos_x_prefix/lib/libSDL2.a" \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
    -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework GameController \
    -o "$ndos_x_binary"
xcrun simctl spawn "$ndos_x_simulator" "$ndos_x_binary"
