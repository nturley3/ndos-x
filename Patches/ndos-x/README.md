# nDOS-X host patches

Numbered patches under `dosbox-x/` and `SDL2/` apply in filename order to the exact dependency pins in `Experimental/dependencies.json`. Keep iOS integration in nDOS wherever practical. Preparation intentionally leaves the dependency working tree patched, while the committed gitlink remains the upstream commit.

Run `python3 scripts/prepare-ndos-x.py` after initializing submodules. Patches are applied to both the dependency index and working tree so added files are verified too. It verifies the complete expected patched tree, accepts repeat runs, and refuses unexpected tracked or untracked modifications without resetting them. To update upstream, preserve local work, reverse the verified patch set with `python3 scripts/prepare-ndos-x.py --unprepare`, explicitly select the new dependency revision, refresh the numbered patches, update the manifest, and run the integration checks.
