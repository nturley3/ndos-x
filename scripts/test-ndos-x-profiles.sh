#!/bin/bash
set -euo pipefail
ndos_x_root=$(cd "$(dirname "$0")/.." && pwd)
ndos_x_check="$ndos_x_root/output/ndos-x-profile-check.app/Contents"
mkdir -p "$ndos_x_check/MacOS" "$ndos_x_check/Resources"
cp "$ndos_x_root/Experimental/ndos-x.conf" "$ndos_x_check/Resources/ndos-x.conf"
xcrun clang -fobjc-arc -Wall -Wextra -I"$ndos_x_root/Experimental/Host" \
    "$ndos_x_root/Experimental/Tests/profile-check.m" \
    "$ndos_x_root/Experimental/Host/NDOSXProfiles.m" -framework Foundation \
    -o "$ndos_x_check/MacOS/profile-check"
"$ndos_x_check/MacOS/profile-check"
