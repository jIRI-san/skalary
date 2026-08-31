# Domain Model

<!-- Capture project-specific terms, actors, invariants, and boundaries that affect the design. -->

## Terms and meanings

- **Canonical Capture bytes**: workflow-log content normalized to LF for deterministic comparison.
- **Checkout representation**: platform-dependent worktree bytes, which may use CRLF on Windows.
- **Permitted residue**: exactly one staged or unstaged Capture path left by an interrupted publication.
- **StatePath**: the six-field epic run checkpoint path; absence is a fail-closed terminal condition.

## Actors and boundaries

- Container autopilot owns implementation, tests, synchronization, and commits.
- The Windows host runs validation only and supplies the observed failure evidence.
- Existing Git and workflow writers remain the publication and status authorities.

## Invariants

- `a5ad22` review records, Wrap decisions, and retained findings are never rewritten.
- Cross-platform normalization never broadens the set of admitted changed paths.
- Missing or ambiguous state and residue remain explicit failures.
