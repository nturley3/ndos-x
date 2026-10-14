#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
prefix="$root/output/ndos-x-engine/iphonesimulator-arm64/prefix"
[[ -f \
    "$root/output/ndos-x-engine/iphonesimulator-arm64/libdosbox-x.a" ]] || { echo 'Build the Simulator engine first: NDOS_X_SDK=iphonesimulator bash scripts/build-ndos-x-engine.sh' >&2; exit 1; }
python3 "$root/Experimental/Tests/make-mouse-probe.py" "$root/output/guest-mouse-probe.h"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang++ -target arm64-apple-ios15.4-simulator -isysroot "$sdk" \
    -std=c++14 -fobjc-arc -DSDL_MAIN_HANDLED \
    -I"$root/Experimental/Host" -I"$root/output" -I"$root/vendor/SDL2/include" \
    "$root/Experimental/Tests/guest-mouse-check.mm" "$root/Experimental/Host/NDOSXHost.mm" \
    "$root/output/ndos-x-engine/iphonesimulator-arm64/libdosbox-x.a" "$prefix/lib/libSDL2.a" "$prefix/lib/libpng16.a" \
    -lz -liconv -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
    -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework GameController -o "$root/output/ndos-x-guest-mouse-check"
ndos_x_result=0
xcrun simctl spawn "${1:-booted}" "$root/output/ndos-x-guest-mouse-check" > "$root/output/ndos-x-guest-mouse-result.log" 2>&1 || ndos_x_result=$?
tail -8 "$root/output/ndos-x-guest-mouse-result.log"
exit "$ndos_x_result"
