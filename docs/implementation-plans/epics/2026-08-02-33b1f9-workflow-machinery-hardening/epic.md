# 33b1f9: Workflow machinery: acquisition, evidence, and the learning loop
<!-- epic-id: 33b1f9 -->
<!-- Folder naming: epics/<yyyy-mm-dd>-<6hex>-<slug> · epic-id is the canonical handle. New-Epic.ps1 fills these in. -->

## Goal

Improve plan **acquisition**, **implementation**, and the **learning loop** so the machinery measurably gets better over time instead of rediscovering the same defects.

**Desired outcome.** skalary's workflow machinery enforces what it asserts: receipts, reports and gates reflect what actually ran; the learning loop retains what it learns across phases and runs; and the plugins behave correctly in a repo that is not skalary.

**Success signals.**

- A receipt or report can distinguish a degraded run from a clean one.
- CI fails if any of this epic's fixes is reverted.
- The ledger accumulates from every phase, not only the last.
- `/si` leaves a durable record of what it proposed and what was declined.
- An install in a non-skalary repo resolves every asset its skills reference.
- A `/cip` interview asks *why*, and the operator recognises their own intent in the resulting plan.

**Non-goals.**

- Re-opening the review concern taxonomy — `b0c0d3` settled it.
- Changing autopilot's plan contract or safety rules — plan `001`'s decisions stand.
- Adding workflow skills beyond those already parked in `docs/design-notes/explorations/`.
- Pointing the plugins at the other project during this epic; that happens after every child lands.

**Definition of done.** Operator's bar: acquisition, implementation and the learning loop all improved, such that running the full loop on a fresh plan shows the ledger, the receipt and the `/si` record each reflecting what actually happened.

## Child plans

<!-- child-plans:start -->
| Plan | Slug | Depends on |
|---|---|---|
| `1936cb` | learning-loop-durability | — |
| `2366ad` | cross-repo-si-and-standards | `1936cb`, `79cfe1` |
| `34088e` | consumer-install-correctness | — |
| `768d7b` | gates-real-and-affordable _(archived)_ | — |
| `863d97` | evidence-receipt-truth | — |
| `c21cdc` | review-report-as-data | — |
| `79cfe1` | concern-registry-and-generated-agents | — |
| `ca8ba8` | review-corroboration-truth | `c21cdc` |
| `583308` | autopilot-container-toolchain | — |
<!-- child-plans:end -->

Membership is the `<!-- epic: 33b1f9 -->` marker in each child `plan.md`; the table above is a generated
mirror that `New-Epic.ps1` rewrites. Run `Get-PlanState 33b1f9` for live rollup and the next unblocked
child plan.

## Decomposition notes

**Source.** The original children trace to evidence from `b0c0d3`: its 44-finding step 10.7 gate, its `/dr` round, the first real `/si` harvest, and the operator's `align:partial` acceptance. The clusters are catalogued in [review-system-enforcement-gaps.design.md](../../../design-notes/explorations/review-system-enforcement-gaps.design.md). Plan `583308` was added from operator feedback after repeated container runs exposed that common agent utilities such as `ripgrep` were absent from the image.

**Seam chosen: artifact contract, not lifecycle stage.** The operator's done bar names three stages (acquisition, implementation, learning loop), but "implementation" is not one seam — it is three artifacts with independent contracts: the evidence receipt, the review report, and the gates. Cutting on lifecycle alone would produce layer-per-plan, where no child delivers observable value until its siblings land. Cutting on artifact contract gives each child its own revertible surface.

**Why not one plan.** The queue spans ~8 Critical review findings, eight enforcement-gap clusters, three accepted `/si` candidates, six parked explorations and two `/dr` headline findings, across the review, receipt, ledger, install and CI surfaces. `b0c0d3` was smaller and still overran its advisory phase budget on 5 of 10 phases.

**Edges.** `cross-repo-si-and-standards` depends only on durable local learning from `learning-loop-durability` and the concern source/generator from `concern-registry-and-generated-agents`. `review-corroboration-truth` retains archived `review-report-as-data` as prior implementation authority. The remaining active children have no dependencies and are independently schedulable.

**Prior art reconciled.** *Reuses* plan `001`'s agent-safety rules and exit-code contract, and plan `002`'s receipt model, install confinement and hash verification. *Extends* `002`'s receipt concept to the evidence receipt — a different artifact sharing the same inability to describe a degraded run. No prior decision is superseded and none conflicts.

**Execution order.** The operator selected `gates-real-and-affordable` first; it is now archived and supplies the feedback-loop baseline used by later children. Current execution follows the live cross-epic dependency graph.

## Before each child run

Run a quick simplicity and consistency review against the child's confirmed intent and the current epic graph before implementation starts. Check that every mechanism is necessary, shared behavior has one owner, no child duplicates another child's machinery, and every dependency is required by delivered behavior rather than speculative infrastructure. Classify the result as `keep`, `simplify`, `split`, or `defer`; resolve blocking simplification findings before running the plan and record the decision in the plan's existing decisions or references. Reuse the rubric in [the 2026-08-22 simplification review](../2026-08-22-plan-simplification-review.md); do not create a new review-state system for this gate. Apply this checklist manually until plan `25aa23` adds the same prompt-level gate to `/ci`.
