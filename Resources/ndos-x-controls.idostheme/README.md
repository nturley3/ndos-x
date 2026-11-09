# nDOS-X touch controls

This theme contains only gamepad scenes and their assets. nDOS-X uses it for touch controls while retaining the established app theme for its shell. The original iDOS build continues to use `default.idostheme`.

Scenes retain the original nDOS control arrangements, with decorative plates removed, mode/edit buttons added to landscape, and larger portrait utility targets. `sources/` contains original SVG artwork for the refreshed translucent controls; `assets/` contains transparent 8-bit PNG exports. The artwork is distributed under the repository’s GPL license. Button labels are drawn by UIKit so custom bindings remain readable.

Run `bash scripts/render-ndos-x-controls.sh` from the repository to regenerate PNGs with ImageMagick. The app build consumes committed exports and does not require an image renderer. SVG strokes have explicit opacity to keep exports consistent with ImageMagick’s internal SVG renderer.
