# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Operator direction (2026-08-14)

`/cep` must run a focused epic coherency review in addition to its interview, seams gate, and operator cut
confirmation. This review is distinct from the detailed implementation-plan review each child receives.

## Intended review boundary

- Verify goal, desired outcome, success signals, non-goals, and definition of done are collectively covered.
- Verify children are vertical, independently executable, revertible, and useful at operator checkpoints.
- Detect missing, redundant, or overlapping children and ownership split across children.
- Verify shared contracts have one owning child and dependency edges are necessary, direct, and acyclic.
- Reconcile overlap with active and archived plans plus existing epics.
- Verify the decomposition includes both an early MVP path and eventual complete delivery.
- Exclude child implementation details, typed evidence, and code-level design; child `/cip` plus `/dr` own those.

## Orchestration relationship

This child depends on `8a0644` and consumes its shared fleet scheduler. Epic review uses the same four-agent
in-flight cap, declared waves, attendance states, and provider-throttling policy as `/cip`, `/ci`, `/cr`, and
`/dr`; it does not create another dispatch implementation.

## Existing contract to extend

- `.github/skills/cep/SKILL.md` — current interview, accepted-cut, scaffold, and child handoff sequence.
- `.github/skills/cep/assets/decomposition-guide.md` — `epic-intent`, `seams`, verticality, dependency, and
	independent-executability checks currently performed by the orchestrator itself.
- `b0c0d3` REQ-15 — epic index and independently executable child-plan substrate.
