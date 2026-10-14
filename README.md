# nDOS-X

nDOS-X brings MS-DOS games, programs, and early Windows computing to iOS and iPadOS. It is a significant refactor of my original nDOS project, built around the DOSBox-X core. The iPad is my primary focus, and I'm also working to keep the experience enjoyable on iPhone.

The project is under active development. Moving to DOSBox-X gives me a foundation for exploring more of the DOS and Windows 95/98 era on modern Apple devices.

## What you can do today

- Run DOS games and programs with the DOSBox-X core.
- Use keyboard input, touch-based mouse movement, and a connected mouse.
- Copy programs, disk images, and configuration files through the Files app.
- Choose separate machine configurations for different software and operating systems.

Most testing currently takes place on iPad, with more iPhone testing and refinement still needed. A good experience on both iPadOS and iOS remains a goal. Some original nDOS features, including Apple Pencil shortcuts, package reopening, and media-mount controls, are still pending in nDOS-X. Switching machine configurations currently requires a full app relaunch. See the [detailed guide](docs/ndos-x/README.md) for setup instructions, current limitations, and known issues.

## Tested Operating Systems and Software

✅ Tested and working · ❌ Tested and not working · ⏳ Pending testing

| Operating system or software | Status |
| --- | --- |
| Windows 98 SE | ✅ Working |
| Microsoft Plus! 98 | ✅ Working |

I'll add more results as testing continues.

## Getting started

1. Follow the [build and installation guide](docs/ndos-x/README.md#reproduce-the-build) to build nDOS-X with Xcode and [install it on your iPad](docs/ndos-x/README.md#physical-ipad-build-and-launch).
2. Launch the app, then open **Files → Browse → On My iPad → nDOS-X** (or **On My iPhone → nDOS-X** on iPhone). Copy DOS games and programs into the `dos` folder. The default configuration maps this folder to `C:`; run `RESCAN C:` in DOS after copying files to refresh the directory listing.
3. Select a configuration and tap **Start**. You can add or edit `.conf` files in the `config` folder through Files to set up different machines. See [machine configurations](docs/ndos-x/README.md#choose-a-machine-configuration) for disk-image paths and startup commands; a configuration does not install Windows for you.

Shut down Windows inside the guest before closing the app or relaunching to change configurations.

## Why I'm building this

I'm a retro computing enthusiast, especially when it comes to games from the MS-DOS and early Microsoft Windows era. I'm also a fan of Apple products, particularly the iPad. Playing those old games on a touchscreen brings back memories using modern gear.

I wanted a coding project that would be fun while helping me learn the Apple SDKs and iOS development, even with an older Objective-C codebase as the starting point.

Why nDOS? Because I lack imagination and couldn't think of a better name when I forked iDOS 😆. The name gave me room to try different things. The X now reflects the move to DOSBox-X.

## Development and future plans

I'm a full-time dad and a professional IT Architect. I work on this project when I have spare time, so progress depends on what life allows. Issues, testing reports, and pull requests are welcome.

My focus is improving the DOSBox-X integration, testing more DOS and early Windows software, and refining the interface for both iPad and iPhone. Longer term, I'd still like to move more of the app's interface to Swift for maintainability. That's an ambition rather than a scheduled milestone.

Build instructions, configuration details, validation notes, and the upstream update process live in the [development guide](docs/ndos-x/README.md).

## History and acknowledgements

nDOS began as a fork of iDOS/DOSPad, using the original DOSBox core with patches and customizations. nDOS-X continues that project with a significantly refactored integration built around DOSBox-X. The original nDOS engine remains available through the retained `iDOS` build scheme.

Thanks to the [DOSBox project](https://www.dosbox.com/) and the DOSBox-X team for making it possible to revisit these games and systems.

Thanks to @litchiedev for iDOS/DOSPad and for bringing DOSBox to iOS and iPadOS. I respect that work, and this project remains my space to learn and experiment with retro computing on the iPad.
