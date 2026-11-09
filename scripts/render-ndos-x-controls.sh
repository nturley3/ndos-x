#!/bin/bash
# Export original SVG control artwork as transparent 8-bit PNGs for UIKit themes.
set -euo pipefail
ndos_x_root=$(cd "$(dirname "$0")/.." && pwd)
ndos_x_theme="$ndos_x_root/Resources/ndos-x-controls.idostheme"
command -v magick >/dev/null || { echo 'Install ImageMagick to regenerate control assets.' >&2; exit 1; }
for ndos_x_svg in "$ndos_x_theme"/sources/*.svg; do
    ndos_x_name=$(basename "$ndos_x_svg" .svg)
    magick -background none "$ndos_x_svg" -depth 8 "PNG32:$ndos_x_theme/assets/$ndos_x_name.png"
done
