# Evolution Log

## Round 1 - 2026-08-16

### Issues found

- Review run `8e0b6b5e-65f4-4f91-9b3c-9c070b0bd251` completed 14/14 tasks and reported 71 merged findings: 1 Critical, 31 High, 35 Medium, and 4 Low.
- Findings clustered around independent policy oracles, non-vacuous evidence, generated-region integrity, hostile registry data, path/reparse confinement, interruption/version semantics, stale dogfood pruning, gate inventory, suite cost, and unchanged review-run authority.
- Finding 1 was rejected: it classified the orchestrator's review invocation scope as plan content rather than identifying a defect in the plan.

### Issues fixed

- Kept the schema enum and model allowlist independent from registry-authored guidance.
- Added immutable pre-generation digests, hostile/refusal fixtures, full safety assertions, output byte bounds, non-blind mutation tests, and bounded process execution.
- Defined one existing generated-region grammar, full-graph render-before-write behavior, canonical confinement, link/reparse rejection, bounded diagnostics, and separate Fast/Slow evidence.
- Added active roster generation, concrete gate inventory/runtime evidence, per-step downstream convergence, and deterministic review-run non-regression checks.
- Assigned bounded stale installed-agent pruning to `Sync-Dogfood.ps1` without merging generator/downstream ownership.

### Issues deferred or accepted

- Accepted: an interrupted concern-generation rerun may cause at most one harmless extra patch bump. Missing a required version move remains forbidden and fault-tested.
- Rejected: durable bump journal and staged multi-file transaction machinery; deterministic rerun convergence remains the selected simplicity boundary.

## Round 2 - 2026-08-16

### Issues found

- Review run `eec4589b-372a-40a8-969a-e73a67ab2d11` completed 14/14 tasks and reported 30 merged findings: 4 Critical, 14 High, 10 Medium, and 2 Low.
- Findings exposed missing migration provenance, cross-format boundary ambiguity, real-host capability wiring, exact test identifiers, dogfood serialization, marker bootstrap, literal substitution, numeric execution bounds, version-last ordering, and discovery/architecture ownership.

### Issues fixed

- Bound migration digests to immutable Git source bytes and separated them from live generated-output checks.
- Replaced the generic generated-region claim with whole-file agent output, one named Markdown marker grammar, structured manifest reconciliation, and runtime registry reads for PowerShell consumers.
- Wired capability to the existing Linux/Windows `gate:repository-validation` host and replaced the nonexistent suite marker with existing named tests.
- Added literal single-pass substitution, structural escape refusals, 8 KiB per-agent and aggregate byte limits, marker adoption semantics, and per-family non-blindness cases.
- Pinned numeric runspace/process/full-chain limits, version-last mutation, baseline-versus-candidate version gating, and joint-writer evidence.
- Put dogfood copy/prune under the shared mutation lock with candidate bounds, `-WhatIf` drift, path receipts, and fail-closed reparse behavior.
- Added design-note discovery ownership, architecture-contract update, and human architecture regeneration.

### Issues deferred or accepted

- Accepted: Linux and Windows CI Fast/Slow gates are authoritative for platform runtime. Container-local measurements are supplemental; no autonomous receipt rewrite or human finalization gate is added.
- Preserved: convergence without a journal may cause at most one extra patch bump after interruption.

## Round 3 - 2026-08-16

### Issues found

- Review run `6453ba70-bb62-45a1-82b5-b3fc70d4d3dd` completed 14/14 tasks and reported 42 merged findings: 18 High, 23 Medium, and 1 Low.
- Findings concentrated on receipt-safe dogfood deletion, durable no-journal version debt, missing Slow-tier enforcement, governance ordering, capability-wrapper behavior, migration provenance lifetime, and exact evidence identifiers.

### Issues fixed

- Moved indexed design-note ownership and suite-tier declarations before the implementation they govern.
- Made provenance explicitly migration-only, fail-loud on unavailable Git objects, and separate from ongoing live-output tests.
- Named `Sync-ReviewConcerns.ps1` as the marker/identity owner; required idempotent per-file adoption and one validated cached runtime reader.
- Replaced the parser-blocking PowerShell directive with a 7.0-compatible bounded 7.6/schema capability check and added container/CI preflight coverage.
- Added aggregate case/time caps, tainted determinism cases, the real architecture freshness script marker, and the evolution-log asset link.

### Issues deferred or accepted

- `KPI-1`: receipt and modification precedence for dogfood deletion remains unresolved.
- `KPI-2`: durable version-bump debt without a journal remains unresolved.
- `KPI-3`: Slow-tier runtime authority remains unresolved because the current runner explicitly applies no budget to Slow.
- Three DR rounds are complete. Further review requires an explicit operator choice.

## Implementation readiness resolution - 2026-08-17

- **KPI-1 resolved:** dogfood prune authority is subordinate to receipts and user modifications. Under the mutation lock, deletion requires generated ownership, manifest absence, Git tracking, exact `HEAD` bytes, and no receipt owner; uncertainty fails closed.
- **KPI-2 resolved:** version-first Git-baseline convergence replaces version-last debt. Dirty/local runs use `HEAD`; clean CI supplies an explicit event base. The version advances before payload writes, so interruption leaves a safe, durable signal and rerun completes without a journal or duplicate bump.
- **KPI-3 resolved:** plan `31a3ef` subsequently added the manifest-owned 1,800-second Slow ceiling, `SlowMeasurementRecord`, and `test:RunUnitTests.SlowOverBudgetFails`. This plan reuses that contract, assigns heavy tests to Slow before first run, records a supplemental current-tree measurement, and forbids ceiling raises.
- No Known Plan Issues remain. A targeted implementation-readiness review follows these decisions.

## Targeted readiness review - Round 4 - 2026-08-17

- Review run `eb870e03-017a-44c7-b928-a567650f2117` completed 14/14 tasks and found three Critical, ten High, ten Medium, and one Low issue in the first readiness resolution.
- Added durable whole-file ownership through a generated marker plus baseline generated inventory.
- Made per-plugin version changes atomic, added explicit-base input grammar/refusal behavior, and assigned candidate-vs-base proof to a named workflow gate.
- Made dogfood authority receipt-subordinate and inventory-bound, batch-loaded receipt/Git state, enumerated every refusal class, and defined `-WhatIf` lock-state behavior.
- Assigned exact Fast/Slow test files atomically, required `npm run test:slow` after integration changes, and removed the unsupported supplemental-record claim unless the declared writer contract can emit it.
- Moved architecture maintenance into the dogfood behavior step and added concrete focused verification to every implementation step.
- No open architecture decision remains; targeted round 5 verifies the corrected execution contract.

## Targeted readiness review - Round 5 - 2026-08-17

- Review run `416dcea0-e36c-430e-b79f-b7ceb39a540a` completed 14/14 tasks. Its dispatch-only Critical classification was rejected; eight High findings identified remaining execution-contract precision gaps.
- Prior generated ownership now comes from the explicit prior-base inventory, so committed removal does not erase prune authority.
- Dogfood has closed exits, complete receipt-store validation, `-WhatIf` drift semantics, named remedies, and exhaustive refusal evidence.
- The CI event base is passed to both payload-version and dogfood gates; gate inventory and documentation owners are explicit.
- The unsupported conditional supplemental Slow receipt was removed. Existing Slow ceiling and CI verdicts are reused; Fast drift work has a concrete sub-5-second reference threshold.
- Exact focused tests and both Fast/Slow commands are named in every affected step. No High or Critical implementation blocker remains in the plan text.
- A final correctness/reliability blocker recheck found none after adding preflight-atomic/resumable dogfood semantics, total status shapes, and shared manifest-writer serialization.