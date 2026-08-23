# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Epic `33b1f9` desired outcome: installed plugins must work in a repository that is not skalary.
- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 49-52: `/cep` dogfooding exposed source/install assumptions and scaffold validation defects while creating the epic.
- `docs/design-notes/architecture/plan-workflow.design.md` and `docs/design-notes/architecture/plugin-registry.design.md`: installed script bundling, scaffold declarations, and distribution synchronization contracts.
- [2026-08-22 simplification review](../../epics/2026-08-22-plan-simplification-review.md) — approved the manifest fixture, runtime scan, active-plugin smokes, scaffold lifecycle, and drift checks while removing workflow-limit, fleet, and retirement-transition scope.

## Prior-art reconciliation

- **Reuses** archived plan `b0c0d3` REQ-19 and its install/scaffold decision: every runtime read is installed or created by a declared first-use owner; installer confinement is unchanged.
- **Extends** `c21cdc` REQ-2, REQ-7, and REQ-13: its isolated CR/DR installed lifecycle becomes one probe in an active-manifest matrix covering every plugin; the review-run v1 contract remains owned by `c21cdc`.
- **Reuses** `ARCH-Install-Confinement`: install/update writes remain under `.github/`; paths outside it are prompt/script-driven first-use scaffolds only.
- **Uses** `asset-scanner-root-bound.design.md` as prior analysis for scanning declared and undeclared runtime roots without promoting a new architecture contract.

## Confirmed interview

- Operator confirmed all shipped runtime surfaces, container whole-plan execution, and no new packages on 2026-08-15. The 2026-08-22 simplification removes unrelated workflow-limit ownership while preserving foreign-install correctness.
- No API, UI, persistent application data, external service, credential, or live-network change is required. Deterministic diagnostics remain bounded and secret-free.

## Superseded design-review mechanics

- The earlier hard dependency on `cda9da`, reverse fleet dependency proposal, workflow-limit parity platform, custom probe report protocol, and hosted receipt requirements are superseded by the simplicity decision. Existing installer confinement and test infrastructure remain controlling.
