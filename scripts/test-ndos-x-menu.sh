#!/bin/bash
set -euo pipefail
ndos_x_root=$(cd "$(dirname "$0")/.." && pwd)
ndos_x_engine="$ndos_x_root/output/ndos-x-engine/iphonesimulator-arm64"
ndos_x_prefix="$ndos_x_engine/prefix"
[[ -f "$ndos_x_engine/libdosbox-x.a" ]] || { echo 'Build the Simulator engine first.' >&2; exit 1; }
ndos_x_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang++ -target arm64-apple-ios15.4-simulator -isysroot "$ndos_x_sdk" \
    -std=c++14 -fobjc-arc -DSDL_MAIN_HANDLED -DNDOS_X_HOST \
    -I"$ndos_x_root/Experimental/Host" -I"$ndos_x_root/vendor/SDL2/include" \
    -I"$ndos_x_engine/dosbox-x" -I"$ndos_x_root/vendor/dosbox-x/include" \
    "$ndos_x_root/Experimental/Tests/menu-check.mm" "$ndos_x_root/Experimental/Host/NDOSXHost.mm" \
    "$ndos_x_engine/libdosbox-x.a" "$ndos_x_prefix/lib/libSDL2.a" "$ndos_x_prefix/lib/libpng16.a" \
    -lz -liconv -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
    -framework CoreAudio -framework AudioToolbox -framework AVFoundation -framework GameController -framework CoreMotion -framework CoreHaptics \
    -o "$ndos_x_root/output/ndos-x-menu-check"
ndos_x_test_directory="menu-check-$(uuidgen)"
for ndos_x_phase in save isolated restore; do
    ndos_x_result=0
    xcrun simctl spawn "${1:-booted}" "$ndos_x_root/output/ndos-x-menu-check" "$ndos_x_phase" "$ndos_x_test_directory" > "$ndos_x_root/output/ndos-x-menu-result.log" 2>&1 || ndos_x_result=$?
    tail -12 "$ndos_x_root/output/ndos-x-menu-result.log"
    if [[ "$ndos_x_result" != 0 ]]; then exit "$ndos_x_result"; fi
    if [[ "$ndos_x_phase" == save ]]; then
        ndos_x_slot=$(sed -n 's/^State fixture: //p' "$ndos_x_root/output/ndos-x-menu-result.log")
        python3 "$ndos_x_root/Experimental/Tests/make-state-fixtures.py" "$ndos_x_slot"
    fi
done

# Optional booted Windows test. Keep all guest writes on a disposable copy.
if [[ -n "${NDOS_X_WINDOWS_IMAGE:-}" ]]; then
    ndos_x_windows_dir=$(mktemp -d "$ndos_x_root/output/windows-state-check.XXXXXX")
    trap 'rm -rf "$ndos_x_windows_dir"' EXIT
    cp "$NDOS_X_WINDOWS_IMAGE" "$ndos_x_windows_dir/windows.img"
    for ndos_x_phase in windows windows-relaunch; do
        xcrun simctl spawn "${1:-booted}" "$ndos_x_root/output/ndos-x-menu-check" "$ndos_x_phase" "$ndos_x_windows_dir/windows.img"
    done
fi
