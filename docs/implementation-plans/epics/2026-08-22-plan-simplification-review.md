# Untouched plan simplification review

Date: 2026-08-22

## Scope and method

This is an advisory review of every child plan at 0 completed steps in active epics `33b1f9` and
`bcece1`. Completed children `768d7b`, `c21cdc`, `583308`, and `cda9da` are excluded. Plan stages such
as `done` mean planning approval, not implementation completion; the live epic rollup and unchecked
steps determine this review set.

Each plan was checked against its plan-local intent and epic goal. The primary question was whether
the smallest mechanism that satisfies the operator outcome and existing architecture contracts was
chosen. Parked explorations and design-review additions are not treated as operator requirements.

Ratings:

- **Critical**: do not start; the plan creates a platform or protocol substantially larger than the outcome.
- **High**: simplify or split before start; major mechanisms or scope are avoidable.
- **Medium**: intent is sound and shape is usable, but implementation machinery should be trimmed.
- **Low**: proportionate; execute with normal scope control.

The initial decisions below are the before-rewrite snapshot. The follow-up section records the accepted
simplifications and second-pass validation after the plans were edited.

## Initial plan decisions

| Epic | Plan | Intended outcome | Complexity | Intent alignment | Decision | Smallest credible shape |
|---|---|---|---|---|---|---|
| `33b1f9` | [`1936cb` learning-loop-durability](../2026-08-02-1936cb-learning-loop-durability/plan.md) | Preserve phase learnings, SI due state, and operator dispositions | **Critical** | Partial | **Redesign** | Keep existing capture/ledger files; add one append-only due record and one SI result record. Reuse a narrow atomic write helper only for those files. Remove the repo-wide writer migration, sharded state topology, repair receipt hierarchy, ranked-set protocol, and suite-fingerprint subsystem. Split upstream proposal lifecycle from phase-learning durability if still required. |
| `33b1f9` | [`2366ad` cross-repo-si-and-standards](../2026-08-02-2366ad-cross-repo-si-and-standards/plan.md) | Carry consumer learning into an upstream-owned proposal safely | **Critical** | Partial | **Split and redesign** | Export one bounded typed candidate artifact, open a clean upstream checkout, and run normal upstream `/si` or `/cip` under upstream rules. Separate review-standard customization into another plan. Avoid generation caches, paged history, isolated launcher infrastructure, dependency-receipt protocols, and review-run v2 in this delivery. |
| `33b1f9` | [`34088e` consumer-install-correctness](../2026-08-02-34088e-consumer-install-correctness/plan.md) | Prove installed plugins work without skalary source paths | **High** | Strong | **Split and trim** | Retain a manifest-derived foreign-repo fixture, runtime-reference scan, representative plugin smoke tests, and scaffold lifecycle checks. Move workflow-limit ownership/parity to its owning workflow plan. Reuse the retirement fixture without making retirement and fleet-limit protocols part of consumer-install correctness. |
| `33b1f9` | [`863d97` evidence-receipt-truth](../2026-08-02-863d97-evidence-receipt-truth/plan.md) | Report passed, skipped, failed, stale, unrun, and waived evidence truthfully | **Critical** | Partial | **Redesign** | Extend the existing evidence result and receipt formatter with explicit statuses and a small plan-local waiver file. Feed structured Pester outcomes into that formatter and block finalization on non-pass/non-waived results. Remove whole-tree digest projection, CAS receipt lifecycle, new exit-code family, dormant v2 cutover, and GitHub API CI-proof authority. |
| `33b1f9` | [`79cfe1` concern-registry-and-generated-agents](../2026-08-08-79cfe1-concern-registry-and-generated-agents/plan.md) | Single-author the seven concern definitions and generated CR/DR agents | **Medium** | Strong | **Trim** | Keep one registry, one deterministic generator, generated agents, and one drift test. Use existing sync/version/registry writers. Drop the new generated-inventory authority, migration provenance protocol, custom atomic multi-plugin transaction, and dedicated dogfood recovery subsystem unless an existing writer cannot satisfy a demonstrated failure. |
| `33b1f9` | [`ca8ba8` review-corroboration-truth](../2026-08-08-ca8ba8-review-corroboration-truth/plan.md) | Prevent suspiciously similar review outputs from increasing confidence | **High** | Partial | **Redesign** | Add a derived corroboration status to the existing review report. Normalize findings, detect exact or clearly near-duplicate support with one documented conservative rule, and force `needs-review` without severity elevation. Avoid review-run v2, policy/version maps, child partitioning, a 16,384-item scoring regime, and a second admission/publication lifecycle. |
| `bcece1` | [`57cc2c` intent-capture-and-rfc](../2026-08-02-57cc2c-intent-capture-and-rfc/plan.md) | Confirm operator intent and approve a concise design before implementation | **High** | Partial | **Redesign** | Use the existing intent/design Markdown assets, required sections, one confirmation marker, and current lifecycle stage writer. `/cip` rephrases and confirms at three checkpoints; edits invalidate the marker. Avoid an Interview Gates schema, installed reader/writer service, locks, repair/version state, revocation protocol, and a new architecture contract. |
| `bcece1` | [`8a0644` dispatch-plan-up-front](../2026-08-08-8a0644-dispatch-plan-up-front/plan.md) | Declare fleet work, run waves of at most four, and report attendance | **Low** | Strong | **Keep** | Current working-tree shape is proportionate: a pure planner plus a run-scoped adapter, with existing review-run state left authoritative. Preserve the explicit non-goals against distributed scheduling, global ledgers, clone management, and activation protocols. |
| `bcece1` | [`25aa23` epic-coherency-review](../2026-08-14-25aa23-epic-coherency-review/plan.md) | Review an accepted epic cut before `/cep` finalizes it | **High** | Partial | **Redesign** | Invoke the existing design-review/fleet path with a fixed epic-coherency scope and store one compact verdict plus resolved findings with the epic. Reuse existing review-run publication. Do not create epic review authority, RFC/state schemas, `review-concerns@2`, dormant APIs, write-ahead orchestration, or a separate activation transaction. |
| `bcece1` | [`4dd933` cross-plan-artifact-context](../2026-08-14-4dd933-cross-plan-artifact-context/plan.md) | Load bounded relevant artifacts from related plans with provenance | **Critical** | Partial | **Redesign** | Add one resolver beside `Get-PlanIndex`: accept resolved plan IDs and an allowlisted artifact kind, use existing layout resolution, enforce path and byte bounds, and return content plus source metadata. Consumers record selected references in existing `references.md`. Defer review-model context roles. Remove sidecar registries copied across plugins, receipt state machines, v2 review lifecycle, budget algebra, and dedicated platform receipts. |
| `bcece1` | [`669ad3` epic-prefixed-plan-folder-naming](../2026-08-14-669ad3-epic-prefixed-plan-folder-naming/plan.md) | Group plan folders by epic without changing canonical IDs | **Critical** | Partial | **Redesign or defer** | First decide whether existing hash-plan migration is worth the disruption; applying the prefix only to new plans is the simplest option. If migration is required, use one `-WhatIf` script that inventories moves, rejects collisions, writes an old/new mapping, performs moves under one lock, and resumes from that mapping. Do not add a general namespace protocol, capability schemas, new exits, review-run contract changes, container relaunches, or four-tuple CI aggregation. |
| `bcece1` | [`6a629b` vertical-implementation-requirement-loop](../2026-08-14-6a629b-vertical-implementation-requirement-loop/plan.md) | Deliver usable vertical phases and recheck intent/requirements | **Medium** | Strong | **Trim** | Keep phase admission, existing evidence crosscheck, decision capture, operator checkpoint, and one-phase autopilot stop/resume. Reuse current plan parsing and workflow-note writers; do not create another checkpoint parser, atomic capture format, or broad parity subsystem unless a focused test proves the existing components insufficient. |
| `bcece1` | [`9fda0b` github-work-hierarchy-synchronization](../2026-08-14-9fda0b-github-work-hierarchy-synchronization/plan.md) | Idempotently create/update a GitHub epic and child issue hierarchy | **High** | Strong | **Redesign** | Deliver GitHub-only v1: deterministic projection, dry-run, operator-confirmed apply, stable local-to-remote mapping, marker-based managed sections, conflict refusal, and second-run no-op. Use `gh` directly behind one small adapter. Defer Azure DevOps abstraction, append-store/state protocols, capability publication, disposable-organization provisioning, and protected hosted smoke orchestration until a second provider or real failure requires them. |
| `bcece1` | [`a5ad22` epic-autopilot-orchestration](../2026-08-14-a5ad22-epic-autopilot-orchestration/plan.md) | Run one eligible child container at a time and pause for verified merge | **Critical** | Partial | **Redesign** | Build a host loop around existing `Get-PlanState`, the existing per-plan launcher, and one small resumable JSON record containing epic, target, current child, branch, run, and outcome. Stop after terminal verification for operator merge, then refresh and repeat. Avoid a new Git-bundle transport, provider/state contract family, large exit matrix, capability audits, delivery concern family, and evidence-only finalization PR. |

## Cross-plan findings

| Pattern | Affected plans | Decision impact |
|---|---|---|
| Narrow outcomes become new protocol families with schemas, state machines, repair, versioning, and activation | `1936cb`, `863d97`, `57cc2c`, `25aa23`, `669ad3`, `9fda0b`, `a5ad22` | Require a demonstrated failure that existing files/helpers cannot handle before approving a new protocol. |
| Multiple plans independently invent atomic stores, receipts, locks, manifests, and recovery semantics | `1936cb`, `34088e`, `79cfe1`, `4dd933`, `669ad3`, `9fda0b`, `a5ad22` | Reuse existing writers and layout resolvers. A plan should own at most the state directly required by its user-visible outcome. |
| Versioned authority is introduced before a minimal behavior is proven | `2366ad`, `ca8ba8`, `25aa23`, `4dd933`, `863d97` | Deliver one current format first. Add compatibility readers only for persisted data that already exists. |
| Dormant-build-then-activate doubles implementation and testing paths | `863d97`, `25aa23`, `9fda0b`, `a5ad22` | Prefer one feature flag or an atomic caller switch after focused tests; avoid parallel dormant and active products. |
| Exact numeric ceilings and exhaustive fault matrices dominate the feature | Most Critical/High plans | Keep security and runtime bounds, but derive them from an observed envelope. Test representative boundaries and known failure classes, not every imagined permutation. |
| Plans absorb adjacent ownership instead of composing it | `2366ad`, `34088e`, `25aa23`, `4dd933`, `a5ad22` | Split unrelated standards, limits, review, and delivery-audit work. Keep one operator-visible outcome per plan. |

## Dependency amplification

The two epics are coupled more tightly than their user outcomes require:

- `57cc2c` cannot start until the Critical `4dd933` context platform and its `669ad3`/`ca8ba8`
  prerequisites complete, even though intent capture can work with existing local assets.
- `8a0644` is now small but waits on `57cc2c`, `6a629b`, and the broad `34088e` plan.
- `25aa23` and `a5ad22` then stack new review and orchestration protocols on that chain.
- `2366ad` combines two outcomes and waits on three broad foundations.

The simplest graph removes dependencies that exist only because plans chose shared infrastructure:

1. Let `57cc2c` use existing assets and index output; make richer cross-plan context optional later.
2. Let `8a0644` depend only on consumers that use its small planner contract, not on completion of all
   consumer-install work.
3. Let `25aa23` call the existing review path rather than waiting for a new concern-authority version.
4. Let `a5ad22` orchestrate the existing per-plan launcher before adding delivered-outcome review.
5. Separate `2366ad` cross-repo transport from review-standard customization.

## Decision queue

| Priority | Operator decision | Plans |
|---|---|---|
| 1 | Approve full redesign before any implementation | `1936cb`, `863d97`, `4dd933`, `669ad3`, `a5ad22` |
| 2 | Split mixed ownership, then redraft the retained outcome | `2366ad`, `34088e` |
| 3 | Replace new review/policy platforms with extensions of current reports and review runs | `ca8ba8`, `25aa23` |
| 4 | Reduce workflow state to existing Markdown assets and markers | `57cc2c` |
| 5 | Deliver a GitHub-only v1 and defer speculative provider/host infrastructure | `9fda0b` |
| 6 | Apply targeted trims during implementation-ready redraft | `79cfe1`, `6a629b` |
| 7 | Keep the current simplified plan | `8a0644` |

Overall recommendation: **1 Keep, 2 Trim, 2 Split, 9 Redesign/Defer**. Do not start a Critical or
High plan until its simpler shape is accepted and its dependency edges are regenerated.

## Post-rewrite validation

The 14 plans were rewritten on 2026-08-22. Confirmed intent remains authoritative; implementation
mechanisms, requirements, risks, decisions, references, and dependency edges were reduced around that
intent. Historical evolution, review, and log artifacts remain unchanged as provenance.

The second pass checked every current `plan.md`, `intent.md`, `requirements.md`, `risks.md`,
`decisions.md`, and `references.md`, both epic mirrors, and the live `Get-PlanState` rollups. It found no
Critical or High blocker, no cycle, no unknown dependency, and no infrastructure-only edge.

| Epic | Plan | Residual complexity | Intent alignment | Dependency consistency | Final decision |
|---|---|---|---|---|---|
| `33b1f9` | [`1936cb` learning-loop-durability](../2026-08-02-1936cb-learning-loop-durability/plan.md) | Low | Strong | Pass | Keep |
| `33b1f9` | [`2366ad` cross-repo-si-and-standards](../2026-08-02-2366ad-cross-repo-si-and-standards/plan.md) | Medium | Strong | Pass | Keep |
| `33b1f9` | [`34088e` consumer-install-correctness](../2026-08-02-34088e-consumer-install-correctness/plan.md) | Medium | Strong | Pass | Keep |
| `33b1f9` | [`863d97` evidence-receipt-truth](../2026-08-02-863d97-evidence-receipt-truth/plan.md) | Medium | Strong | Pass | Keep |
| `33b1f9` | [`79cfe1` concern-registry-and-generated-agents](../2026-08-08-79cfe1-concern-registry-and-generated-agents/plan.md) | Low | Strong | Pass | Keep |
| `33b1f9` | [`ca8ba8` review-corroboration-truth](../2026-08-08-ca8ba8-review-corroboration-truth/plan.md) | Medium | Strong | Pass | Keep |
| `bcece1` | [`57cc2c` intent-capture-and-rfc](../2026-08-02-57cc2c-intent-capture-and-rfc/plan.md) | Medium | Strong | Pass | Keep |
| `bcece1` | [`8a0644` dispatch-plan-up-front](../2026-08-08-8a0644-dispatch-plan-up-front/plan.md) | Medium | Strong | Pass | Keep |
| `bcece1` | [`25aa23` epic-coherency-review](../2026-08-14-25aa23-epic-coherency-review/plan.md) | Medium | Strong | Pass | Keep |
| `bcece1` | [`4dd933` cross-plan-artifact-context](../2026-08-14-4dd933-cross-plan-artifact-context/plan.md) | Low | Strong | Pass | Keep |
| `bcece1` | [`669ad3` epic-prefixed-plan-folder-naming](../2026-08-14-669ad3-epic-prefixed-plan-folder-naming/plan.md) | Low | Strong | Pass | Keep |
| `bcece1` | [`6a629b` vertical-implementation-requirement-loop](../2026-08-14-6a629b-vertical-implementation-requirement-loop/plan.md) | Medium | Strong | Pass | Keep |
| `bcece1` | [`9fda0b` github-work-hierarchy-synchronization](../2026-08-14-9fda0b-github-work-hierarchy-synchronization/plan.md) | Medium | Strong | Pass | Keep |
| `bcece1` | [`a5ad22` epic-autopilot-orchestration](../2026-08-14-a5ad22-epic-autopilot-orchestration/plan.md) | Medium | Strong | Pass | Keep |

### Measured reduction

| Epic | Untouched steps before | Steps after | Reduction |
|---|---:|---:|---:|
| `33b1f9` | 80 | 34 | 46 |
| `bcece1` | 82 | 51 | 31 |
| **Total** | **162** | **85** | **77 (47.5%)** |

### Final ownership and graph

- `1936cb` owns durable local learning and SI due/result records; `2366ad` consumes it for bounded
  upstream handoff.
- `79cfe1` owns concern authoring/generation; other review plans consume generated concerns and
  existing review-run v1.
- `863d97` owns truthful evidence outcomes; the only cross-epic edge, `6a629b -> 863d97`, consumes
  that delivered behavior at phase close.
- `4dd933` owns bounded historical artifact resolution beside `Get-PlanIndex`; consumers do not invent
  sidecar registries or receipt lifecycles.
- Archived `c21cdc` remains the explicit delivered review-run v1 authority for `ca8ba8` and the CR/DR
  adapter in `8a0644`; as a completed dependency it documents ownership without blocking execution.
- `8a0644` owns the small run-scoped dispatch planner and `25aa23` consumes it without adding another
  scheduler. Sequential epic autopilot reuses the existing per-plan launcher directly.
- `57cc2c`, `34088e`, `669ad3`, and `9fda0b` use existing workflow, install, path, and command
  machinery rather than creating shared platforms.

### Epic coherency guardrail

Plan `25aa23` now covers the failure that triggered this review. It classifies each finding as
`local fix`, `required shared contract`, or `speculative platform`; requires a demonstrated cross-plan
invariant before shared architecture is allowed; detects duplicated mechanisms, unclear ownership, and
infrastructure-only dependencies; and records concrete `keep`, `simplify`, `split`, or `defer` outcomes.
Minor design-review findings cannot justify new schemas, protocols, stores, state machines, compatibility
layers, providers, or dependencies. The same lightweight check runs before each epic child, records its
result in existing epic/plan prose, and uses Git history instead of a new review-state system.

Final verdict: **all 14 plans are consistent enough to run, subject to the documented pre-run simplicity
and consistency check before each child starts.**