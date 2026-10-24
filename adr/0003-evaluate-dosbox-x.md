# Evaluate DOSBox-X behind the nDOS interface

nDOS-X is an isolated experimental app that evaluates DOSBox-X with SDL2 as a replacement engine for nDOS. DOSBox-X carries Windows 95/98 CPU and device compatibility work that would otherwise require intertwined backports into the existing engine. Keep the established nDOS engine available while testing the alternative on physical iPad hardware without JIT or a debugger.

Maintain an embedding boundary because upstream provides an application rather than a stable embedding API. The upstream baseline and local modification strategy are recorded in [Preserve the upstream DOSBox-X core with reproducible host patches](0006-upstream-core-and-host-patches.md). Do not replace the regular engine until Windows and DOS compatibility and performance have been evaluated.
