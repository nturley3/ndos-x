# Preserve the upstream DOSBox-X core with reproducible host patches

Recorded retrospectively on 2026-10-23. Original decision date unknown; the implementation and a brief record of this decision in ADR 0003 were present in repository import `b3341b0`. The project author confirmed the upstream-consistency rationale during retrospective review.

Keep the DOSBox-X core pinned to an official upstream commit as a Git submodule, and maintain necessary host changes as reviewed, numbered patches in this repository. Keep iOS integration in the host wherever practical. This preserves an identifiable upstream baseline, makes local changes explicit, and keeps upstream upgrades reviewable, at the cost of maintaining and refreshing the patch set as upstream evolves. SDL2 follows the same dependency workflow.

Preparation applies patches in filename order to the dependency's index and working tree; the submodule HEAD and committed gitlink remain at the pinned upstream revision. The preparation script verifies the expected patched tree, accepts repeat runs, and refuses unexpected local changes rather than resetting them. A modified submodule after preparation is therefore expected and does not represent a new upstream revision.

Upgrades require preserving local work, reversing the verified patch set, explicitly selecting a new upstream revision, refreshing patches and the dependency manifest, and repeating integration checks. Review and commit the gitlink, manifest, and patch changes together.

Implementation evidence: [dependency pins](../Experimental/dependencies.json), [patch policy](../Patches/ndos-x/README.md), [preparation script](../scripts/prepare-ndos-x.py), and [upstream update procedure](../docs/ndos-x/README.md#update-upstream).
