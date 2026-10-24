# nDOS-X development guide

nDOS-X is developed independently in [nturley3/ndos-x](https://github.com/nturley3/ndos-x), with `main` as its primary branch. The original [nDOS project](https://github.com/nturley3/ndos) continues in its own repository. The `nDOS-X` shared scheme builds the established nDOS interface with DOSBox-X and SDL2, produces `nDOS-X.app` (`io.turley.ndosx`), and uses its own app container. It does not include the thumbnail extension or document registrations. The scheme launches an optimized Release build without a debugger. The original `iDOS` scheme still builds the retained nDOS engine.

## Reproduce the build

Use Xcode, CMake, and GNU Autoconf. The build script finds Homebrew tools if installed. If Automake is absent, it downloads GNU Automake 1.18.1, verifies its pinned SHA-256, and installs it only under ignored `output/ndos-x-tools`. The first build requires network access for that bootstrap. Current app configurations target ARM64 iOS and ARM64 Simulator.

```sh
git clone --recurse-submodules https://github.com/nturley3/ndos-x.git
cd ndos-x
git submodule update --init --recursive
python3 scripts/prepare-ndos-x.py
xcodebuild -project ndos.xcodeproj -scheme nDOS-X -configuration Release -destination 'generic/platform=iOS' -derivedDataPath output/ndos-x CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ndos.xcodeproj -scheme nDOS-X -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath output/ndos-x-simulator CODE_SIGNING_ALLOWED=NO build
```

Exact upstream revisions are recorded in `Experimental/dependencies.json`: DOSBox-X 2026.10.01 and SDL2 2.32.10. Upstream's bundled libpng is built against the iOS SDK's zlib because its configuration requires PNG even with capture disabled. No host Homebrew libraries are linked into the engine. Upstream dynamic CPU cores and debugger agent are disabled at compilation; the guest uses the normal interpreter.

Prepared engine files and its index intentionally contain the exact numbered host patches, while the submodule HEAD and committed gitlink remain the pinned upstream revision. Preparation verifies both index and working tree, accepts repeat runs, and rejects unexpected tracked, staged, or untracked changes without resetting them.

## Host boundary

The emulator runs on a worker thread. SDL2 uses its dummy video backend and CoreAudio services; the nDOS app owns its UIKit window and presentation. An upstream frame callback copies the guest software surface into a single latest-frame mailbox. A main-thread display link consumes it, including display-mode changes. Target-only compatibility headers retain the existing nDOS keyboard and controller source interfaces without importing private SDL1.3 UIKit objects into the experiment.

Keyboard and relative pointer transitions are queued for the worker. Keyboard transitions are paced so repeated characters and modifiers reach the guest in order. Settings, the engine menu, scene inactivity, and view visibility have independent pause reasons; pausing cancels pending input and releases both held and worker-delivered states before blocking. Stop wakes a paused worker. Engine exit disables further input and displays a stopped session; restarting in the same process is deferred.

The default profile maps guest DOS drive C to the experimental app's `Documents/dos` directory. Its configuration is copied to `Documents/config/ndos-x.conf` on first launch and preserved on subsequent launches; an existing uppercase `NDOS-X.CONF` copy is also recognized. Use copied disk/CD images in this app's own sandbox for Windows configurations. The initial configuration supplies Pentium MMX, 128 MB, S3 graphics, SB16, BIOS PS/2 services, and IDE controllers. Windows 98 SE and Microsoft Plus! 98 have been confirmed tested and working by the project author. Windows disk images and installation media must be supplied and configured separately; the launcher does not create or attach them automatically.

Package reopening, media-mount controls, controller options, direct touch, and Pencil shortcuts are unavailable in the initial experiment. Relative touch pointing, keyboard, mouse buttons, supported display controls, and settings remain available. Gamepad parity, live media changes, saved states, and machine-management UI are deferred.

## Choose a machine configuration

On each full app launch, nDOS-X lists `.conf` files directly inside **Files → nDOS-X → config**. Select a configuration and tap **Start**; the previous selection is highlighted when it still exists. Tap **Refresh** after adding files, or return from Files to refresh automatically before starting. Configurations can be created and edited through Files; there is no in-app config editor.

The default `ndos-x.conf` retains the automatic mapping of `Documents/dos` to `C:`. An existing `NDOS-X.CONF` is also recognized; if both spellings exist, the lowercase file takes precedence. Existing config contents are preserved.

Other configurations are independent machine profiles: they do not inherit `ndos-x.conf`, and the launcher does not supply a `C:` mount or drive-switch command. Copy the default to a new filename, such as `dos-games.conf`, adjust its CPU, memory, graphics or sound settings, and add explicit startup commands under `[autoexec]`. For example:

```ini
[autoexec]
mount c "dos"
c:
```

The host working directory is `Documents`, so relative paths such as `dos` or `images/win98.img` refer to folders or files there. Use those paths rather than an absolute iOS sandbox path, which can change during app updates. A Windows profile can define its own disk-image mounts and boot commands; this picker does not create images or install Windows.

Switching configurations requires a full app relaunch. Shut down Windows inside the guest before stopping the app. If a selected config disappears or cannot be read before Start, nDOS-X shows an error and refreshes the picker without starting the emulator.

## Engine menu

Tap **Engine Menu** (the list icon) in the landscape toolbar or the portrait control strip. In portrait, this replaces the unavailable controller-mapping button. The native sheet follows DOSBox-X's own menu hierarchy, labels, ordering, and checkmarks. Browse categories and submenus, select an action, and keep browsing; tap **Done** or dismiss the sheet to return to the guest.

This version enables CPU speed presets, video frameskip, sound mute, and stereo swap. Other commands remain visible but disabled with an explanation. Desktop dialogs, file pickers, capture, configuration saving, restart, shutdown, and other command families are deferred. Changes affect the running session; the menu does not save changes to the selected profile.

Opening the sheet releases held input and pauses guest execution and audio. A separate worker control queue obtains immutable menu snapshots and dispatches supported upstream commands while the guest stays paused. Closing the menu removes only its own pause reason, so an inactive scene or another pause still keeps the guest paused. All live menu traversal and command dispatch happen on the engine worker; UIKit receives copied state. Closed sessions and engine stop invalidate pending results.

The host disables DOSBox-X's SDL desktop menu regardless of `showmenu` in the profile, while retaining its model for the native sheet. Profiles with `showmenu=true` or no `showmenu` entry therefore no longer enter the blocking desktop menu handler on guest clicks. Keep `autolock=false` in custom profiles so the first click is not consumed by desktop mouse capture. The earlier workaround `showmenu=false` remains harmless. Physical iPad menu and mouse confirmation remains a device acceptance check.

## Load files from the iPad Files app

After installing and launching nDOS-X, open **Files → Browse → On My iPad → nDOS-X**. Copy DOS programs into the `dos` folder and create any game subfolders there. For example, `nDOS-X/dos/GAMES/DEMO` appears as `C:\GAMES\DEMO` inside DOS. The neighboring `config` folder contains the existing configuration files, and `HISTORY` stores command history maintained by the app.

After copying files, run `RESCAN C:` followed by `DIR` in nDOS-X to find them without restarting the app. DOSBox-X caches directory listings, so changes made through Files can remain invisible until the cache is refreshed. The user confirmed that `RESCAN C:` makes newly copied files visible on the physical iPad. Use `TYPE filename.txt` to check a copied text file. Install app updates over the existing app to preserve its files.

DOSBox-X supports `MOUNT C "<host-directory>" -nocachedir` to disable directory caching and enable real-time directory updates. Here, `<host-directory>` is the host folder mapped to the guest drive. nDOS-X currently mounts its `Documents/dos` folder as `C:` in the host launcher (`Experimental/Host/NDOSXEmulator.mm`) without this option; enabling it automatically requires a launcher change. For the current build, use `RESCAN C:` after Files app changes.

The app enables both `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`. Files access exposes the existing Documents directory; it does not change drive mappings or add package launching/document-type registrations. Device acceptance: confirm the folder appears, create a folder and copy a text file into `dos`, verify both from DOS after relaunch, and confirm the existing `TEST.TXT` remains readable. Both Release app bundles were verified to contain the two enabled flags. An in-place Simulator update preserved all nine existing Documents files byte-for-byte; DOS `DIR` and `TYPE` verified a new folder/text file copied directly into its sandbox and read an existing persistent file. The user confirmed the physical iPad Files app shows the `dos` and `config` folders and `HISTORY`, confirmed `dos` maps to `C:`, and reported the file-loading workflow works.

## Validation

```sh
python3 Experimental/Tests/test-preparation.py
bash scripts/test-ndos-x-profiles.sh
# With an ARM64 iPad Simulator already booted:
bash scripts/test-ndos-x-host.sh booted
bash scripts/test-ndos-x-guest-mouse.sh booted true
bash scripts/test-ndos-x-guest-mouse.sh booted omitted
bash scripts/test-ndos-x-menu.sh booted
python3 scripts/test-settings-ui.py --destination 'platform=iOS Simulator,id=DEVICE_UUID' \
    --host nDOS-X --source Experimental/Tests/menu-ui-check.m \
    --test-name EngineMenuTests --derived-data output/ndos-x-menu-ui
```

The real-engine menu check verifies hierarchy, CPU cycles, renderer frameskip, mixer state, hidden/disabled command rejection, and suppression of the SDL menu. The hosted UIKit check exercises navigation, checkmark updates, disabled explanations, dismissal, and stop. The real-host Simulator checks exercise paused menu requests, snapshot ownership, stale sessions, cancellation on stop, pending key releases across nested settings/scene/view pause reasons, repeated characters, modifier ordering, fractional mouse motion, copied frame ownership, and stop while paused. Preparation fixtures cover added/deleted patch files, idempotency, unexpected index/working-tree/untracked changes, and verified reversal for updates.

The profile checks cover default creation and preservation, uppercase compatibility, discovery and sorting, remembered-selection fallback, deleted/unreadable files, and default-versus-custom launch arguments.

Simulator profile validation confirmed the default boots to `C:\>` and a custom profile runs with 32 MB and a 486 CPU, mounts a relative host folder as `D:`, and receives no injected `C:` mount. Remembered selection, missing-file errors before engine startup, background/resume, and output-file persistence across an in-place update and full restart were also verified. Physical-device acceptance for the picker remains pending.

The guest mouse check boots the actual engine, runs a generated DOS COM probe, and verifies INT33 position, motion counters, and movement/button callbacks through the real host queue and SDL frontend. It failed before the mouse fix: relative movement snapped the guest cursor to (0,0), while motion counters remained zero. The app's relative path had skipped the desktop frontend's effective integration/capture state, and the driver still queried SDL window capture when reporting counters. The host route now explicitly supplies relative guest policy and its captured-state query, without capturing an SDL window. Existing app configurations do not need resetting.

The bundled EDIT application was also exercised through the real engine: injected relative motion and a left click opened its File dropdown in Simulator. The user subsequently confirmed the updated build works with touch and a connected mouse on the physical iPad.

Also test the actual guest shell with `SET`, `ECHO`, and `TYPE`, plus a DOS COM program and persistent output file. Host-only checks cannot catch shell/archive integration errors: initial integration exposed a collision between nDOS command-history storage and DOSBox-X's shell command table. The experimental target now gives the history globals distinct names, and an exported-symbol audit found no further host/engine collisions beyond compiler helpers.

| Milestone | Evidence/status |
| --- | --- |
| Separate app build | Integrated Release iOS and ARM64 Simulator builds passed; distinct bundle identifier and no extension/document registrations verified |
| Retained engine | Original nDOS Release iOS build passed after integration |
| Host regressions | All six real-host checks and preparation fixtures passed |
| Guest mouse | INT33 position, counters, movement/button callbacks passed; actual bundled EDIT File menu opened via mouse in Simulator |
| Guest prompt/graphics | Simulator reached C:\> and rendered a DOS mode-13 graphics program |
| Guest shell/persistence | Simulator SET expansion, VER, ECHO/TYPE, COM execution, and output-file persistence across update/restart passed |
| Real scene lifecycle | Simulator background sample blocked the worker; foreground sample resumed the interpreter with the guest visible |
| Device experience | User confirmed coexistence/startup, keyboard/file writes, rotation, settings round trips including background, background/lock resume, and restart persistence; EDIT keyboard/Alt+F works. User confirmed the updated touch and hardware mouse behavior works in EDIT; audio remains untested |
| Windows 98 SE | Project author confirmed tested and working; detailed fresh-installation, driver, reboot/shutdown, persistence, 30-minute stability, and performance evidence has not been recorded |
| Microsoft Plus! 98 | Project author confirmed tested and working |
| Replacement evaluation | Windows 95, selected 2D games, and wider DOS/interface regression evaluation remain later milestones |

Simulator evidence does not establish iPad performance or physical input/audio compatibility. Shut down a booted operating system inside the guest before stopping the emulator; flushing host files is not a substitute for guest shutdown.

## Physical iPad build and launch

Run the following in your own Terminal to unlock the login keychain, build the signed Release app, install it, and launch without a debugger. First find the paired iPad identifier:

```sh
xcrun devicectl list devices
```

Replace the repository path and device identifier below. Each step runs only if the preceding step succeeds. Installation updates the existing app and preserves its Documents folder.

```sh
cd /path/to/ndos-x &&
NDOS_X_DEVICE="<paired-iPad-identifier>" &&
security unlock-keychain "$HOME/Library/Keychains/login.keychain-db" &&
xcodebuild -project ndos.xcodeproj -scheme nDOS-X \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath output/ndos-x -allowProvisioningUpdates build &&
xcrun devicectl device install app \
  --device "$NDOS_X_DEVICE" \
  output/ndos-x/Build/Products/Release-iphoneos/nDOS-X.app &&
xcrun devicectl device process launch \
  --device "$NDOS_X_DEVICE" io.turley.ndosx
```

The keychain unlock prompts for your password through `security`; no password is embedded in the command. Run the command interactively so you can respond to the prompt before signing starts.

Select a configuration and tap **Start** in the app. Confirm both nDOS and nDOS-X coexist and use separate data before copying media into the experiment.

## Update upstream

1. Preserve any work that differs from the reviewed prepared tree; preparation will refuse to overwrite it.
2. Run `python3 scripts/prepare-ndos-x.py --unprepare`. It reverses only an exact reviewed patch set and leaves the upstream submodule checkout pristine.
3. Fetch and explicitly select the desired upstream release/commit in the dependency, update the manifest, and refresh the numbered patches against that revision.
4. Prepare again, rebuild both iOS and Simulator variants, and repeat the host and guest smoke checks. Perform physical-device regression checks and retest Windows 98 SE and Microsoft Plus! 98 with the configured installation media.
5. Review and commit the new gitlink, manifest, and patch changes together. Updates to the original nDOS application are maintained separately in its repository.
