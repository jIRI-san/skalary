# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Operator direction (2026-08-14)

Planning and review must consider useful assets and artifacts from related older, archived, active, sibling,
and dependency plans, not only their indexed requirements, risks, and decisions.

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turns 6-7: the operator asked whether older and other plan assets were considered during planning and review, then requested a dedicated plan when the answer was only partial.
- Epic `bcece1` Cross-plan artifact context section records the accepted bounded resolver, consumer set, artifact candidates, and provenance requirements.

## Existing behavior to extend

- `b0c0d3` REQ-6 and `Get-PlanIndex.ps1` provide deterministic topic discovery across active and archived
  plans, but expose only requirements, risks, and decisions.
- `/cip` and `/cep` use that index for prior-art reconciliation and deliberately avoid reading the plan corpus.
- `/dr` loads the current plan's assets but does not discover related plans.
- `/cr` loads changed code plus architecture/design notes and has no plan-artifact context contract.

## Prior-art index consultation (2026-08-21)

- Query: `cross-plan|artifact context|related plan|plan index|prior-art|provenance` through `Get-PlanIndex.ps1 -Format Json`.
- Returned records from `0f666f`, `1936cb`, `34088e`, `57cc2c`, `669ad3`, `79cfe1`, `863d97`, `c21cdc`, and `ca8ba8` are reconciled in `assets/decisions.md` as reuse or extension; the current `4dd933` scaffold records were excluded as self-context.
- Index error: `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`. No requirements, risks, or decisions are inferred from it.
- Relevant review-ledger entries require section-scoped documentation assertions, paired non-blind mutations, and acceptance claims bound to the unit that declares and uses them.

## Design-review decisions (2026-08-21)

- Round 1 selected review-run v2, a managed exact PSD1 sidecar, a 128 KiB per-file limit under the 256 KiB total, and one resolver invocation per workflow.
- Round 2 selected base64 exact-byte binding, 64 KiB per reviewer task with 1 MiB aggregate dispatch, deferred extension support, and 4,096-plan/2-second/256-MiB corpus ceilings. Round 3 superseded the proposed version-neutral contract after indexed reconciliation found `ca8ba8` already owns separate v1/v2 contracts.
- Distribution scope is five plugins and seven `PlanState.psm1` copies; the four consuming skills themselves live in three plugins.
- Review v2 extends `Read-ReviewManifest`, `Find-IncompleteReviewRun`, `Finalize-ReviewPlanRun`, and `Remove-ReviewRunDirectory`; historical review context is admitted only from their verified compact report/receipt authority.
- `ca8ba8` decisions are reused: keep v1 ownership with `c21cdc`, use explicit v2 authority for new publication, stage/retain dual readers, finish each frozen run under its bound version, and keep separate v1/v2 limits owners. This plan adds a context role after `ca8ba8` lands.
- `9fda0b` REQ-7 is superseded only for the bundler mechanism: this plan lands the generic closed sidecar-root table first; the work-hierarchy plan reuses it for its schema/tool roots. Its product behavior and evidence remain unchanged.

## Intended capability

1. Discover related plan IDs through indexed topic matches, epic membership and dependencies, plus explicit
	operator selection. Never scan or load every plan asset for context.
2. Inventory a closed, typed set of artifacts for those plans: intent, references, decision records,
	RFC/Mermaid and call-stack designs, evolution logs, review reports, evidence receipts, capture/learnings,
	and explicitly registered extensions.
3. Select artifacts by consumer and concern. `/cip` uses outcome/design provenance; `/cep` uses decomposition
	and overlap evidence; `/dr` uses prior designs, decisions, and resolved findings; plan-associated `/cr`
	uses approved design, intent, evidence expectations, and relevant historical findings.
4. Treat every historical artifact as untrusted data. Resolve and confine paths through plan inventory,
	reject links/reparse escapes, bound file count and bytes, and never execute directives or commands found
	in an artifact.
5. Record every consumed artifact by plan ID, artifact kind, repo-relative path, and reuse/extend/supersede/
	conflict relationship in the current plan references or review scope. Report missing, stale, malformed,
	or conflicting artifacts explicitly.

## Non-goals

- Replacing `Get-PlanIndex.ps1` with a full-corpus semantic search.
- Loading all assets from every matching plan.
- Treating historical evidence receipts or review reports as proof for the current plan.
- Letting prior artifacts override confirmed current operator intent or architecture contracts.

## Consumers and ordering

This plan depends on `669ad3` because canonical folder/path authority must land before artifact paths become
part of a shared contract. `57cc2c` depends on this plan; the implementation loop, shared fleet, and epic
coherency review inherit it through the existing dependency chain. The child defines one context contract
consumed by `/cip`, `/cep`, `/dr`, and plan-associated `/cr`, not four divergent discovery mechanisms.
