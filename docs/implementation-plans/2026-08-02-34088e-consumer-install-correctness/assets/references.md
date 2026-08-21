# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Epic `33b1f9` desired outcome: installed plugins must work in a repository that is not skalary.
- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 49-52: `/cep` dogfooding exposed source/install assumptions and scaffold validation defects while creating the epic.
- `docs/design-notes/explorations/review-system-enforcement-gaps.design.md`, Cluster C: constants copied into prose were explicitly deferred here after a design-review handoff was dropped once.
- `docs/design-notes/architecture/plan-workflow.design.md` and `docs/design-notes/architecture/plugin-registry.design.md`: installed script bundling, scaffold declarations, and distribution synchronization contracts.

## Prior-art reconciliation

- **Reuses** archived plan `b0c0d3` REQ-19 and its install/scaffold decision: every runtime read is installed or created by a declared first-use owner; installer confinement is unchanged.
- **Extends** `b0c0d3` REQ-21 and archived plan `768d7b` decision D12: the phase-budget default, plan-size thresholds, and review invocation budget gain structured owner-to-consumer parity rather than another prose copy.
- **Extends** `c21cdc` REQ-2, REQ-7, and REQ-13: its isolated CR/DR installed lifecycle becomes one probe in an active-manifest matrix covering every plugin; the review-run v1 contract remains owned by `c21cdc`.
- **Reuses** `cda9da`'s source-bound retirement protocol and immutable fixture `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/`; this plan tests broad installed-entry-point behavior around that protocol and does not redefine tombstones, state transitions, or fault recovery.
- **Extends** `8a0644`'s preliminary scheduler contract with an owner-local limit handoff. `8a0644` owns the fleet cap and scheduler; this plan owns the parity pattern and consumer-install proof.
- **Reuses** `ARCH-Install-Confinement`: install/update writes remain under `.github/`; paths outside it are prompt/script-driven first-use scaffolds only.
- **Promotes** `asset-scanner-root-bound.design.md` from parked analysis: the scaffold scanner's roots come from the closed grammar rather than from declarations it is supposed to validate.
- Prior-art index: `.github/skills/cip/scripts/Get-PlanIndex.ps1 -RepoRoot . -Format Markdown -Filter 'consumer|install|bundle|scaffold|phase-budget|plan-size|invocation'` on 2026-08-15.

## Confirmed interview

- Operator confirmed all shipped runtime surfaces, owner-local machine values with parity checks, container whole-plan execution, and no new packages on 2026-08-15.
- No API, UI, persistent application data, external service, credential, or live-network change is required. Deterministic diagnostics remain bounded and secret-free.

## Design-review round 1 decisions

- Operator selected a hard `34088e -> cda9da` dependency; `cda9da` owns retirement protocol and this plan tests consumer transition deltas only.
- Operator selected a hard `8a0644 -> 34088e` dependency so downstream fleet work cannot add an unregistered copied cap.
- Final platform proof comes from fresh current-tree Linux and Windows CI receipts.
- Filesystem mutation rejects reparse ancestors and rechecks canonical parent identity immediately before mutation; handle-relative no-follow operations remain a documented residual.
- Runtime overrun falls back to a named blocking integration tier, never reduced coverage or a ceiling raise.

## Design-review rounds 2-3 reconciliation

- Round 2's retained scope states that CI receipt producers, absolute runtime/tier contracts, production source guards, bundle closure, typed scanner inventory, incumbent gate widening, recoverable attendance, retirement ownership, limit discovery, cross-plan evidence, and final budget rerun were resolved before round 3.
- Round 3 bound the probe coordinator to machine-owned concurrency and platform-tier deadlines; required explicit credential/profile isolation and recoverable network state; moved persistent scanner data to scanner-owned policy; confined probe entrypoints and scaffold bindings; serialized shared generated surfaces; and bound final evidence to an attested parent candidate.
- Round 3 also corrected the incumbent CI identifier to `gate:review-consumer-install`, kept `cda9da`'s retirement tests authoritative, required capability outcomes to block rather than skip, and placed the review invocation budget in non-validating `x-skalary-limits.reviewInvocationBudget`.
