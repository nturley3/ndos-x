# Keep custom machine profiles independent

Recorded retrospectively on 2026-10-23. Original decision date unknown; the implementation was present in repository import `b3341b0`. The project author confirmed the rationale during retrospective review.

Treat each custom DOSBox-X configuration as an independent machine profile. Custom profiles do not inherit the default profile or receive its host-injected mount and drive-switch commands. We chose ordinary DOSBox-X configuration behavior over the convenience of inherited host defaults, accepting that profiles may repeat configuration and must specify their own mounts and startup commands.

The default profile retains its automatic mapping of `Documents/dos` to `C:`. Custom profiles control their own drive layout and boot sequence, with relative host paths resolved from `Documents`. Independence remains the intended boundary if an in-app editor or in-process switching is added; Files-only editing and relaunch-only switching are current limitations rather than requirements of this decision.

Implementation evidence: [profile launch arguments](../Experimental/Host/NDOSXProfiles.m), [emulator working directory](../Experimental/Host/NDOSXEmulator.mm), and [machine configuration documentation](../docs/ndos-x/README.md#choose-a-machine-configuration).
