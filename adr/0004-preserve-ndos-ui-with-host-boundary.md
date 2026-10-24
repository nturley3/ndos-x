# Preserve the nDOS interface through a UIKit host boundary

Recorded retrospectively on 2026-10-23. Original decision date unknown; the implementation was present in repository import `b3341b0`. The project author confirmed the rationale during retrospective review.

Keep UIKit responsible for the established nDOS interface and presentation, with DOSBox-X running on a worker thread behind a host adapter. We considered letting DOSBox-X/SDL own presentation and chose to preserve the existing nDOS interface, accepting the cost of maintaining a custom embedding boundary.

UIKit queues input and control requests for the worker, which owns live engine state. Guest frames are copied across the boundary for presentation on the main thread; SDL2 uses its dummy video backend. These ownership rules allow the existing interface to operate without taking ownership of live engine objects.

Implementation evidence: [host adapter](../Experimental/Host/NDOSXHost.mm), [emulator startup](../Experimental/Host/NDOSXEmulator.mm), and [host boundary documentation](../docs/ndos-x/README.md#host-boundary).
