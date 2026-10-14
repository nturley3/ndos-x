# Evaluate DOSBox-X behind the nDOS interface

nDOS-X is an isolated experimental app that evaluates DOSBox-X with SDL2 as a replacement engine for nDOS. DOSBox-X carries Windows 95/98 CPU and device compatibility work that would otherwise require intertwined backports into the existing engine. Keep the established nDOS engine available while testing the alternative on physical iPad hardware without JIT or a debugger.

Pin official upstream commits as submodules and keep necessary host modifications as reviewed, reproducible patches in nDOS. This makes the upstream version explicit and keeps future updates reviewable, at the cost of maintaining an embedding boundary because upstream provides an application rather than a stable embedding API. Do not replace the regular engine until Windows and DOS compatibility and performance have been evaluated.
