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
| `2366ad` | cross-repo-si-and-standards | `1936cb`, `34088e` |
| `34088e` | consumer-install-correctness | — |
| `57cc2c` | intent-capture-and-rfc | — |
| `768d7b` | gates-real-and-affordable _(archived)_ | — |
| `863d97` | evidence-receipt-truth | — |
| `c21cdc` | review-report-as-data | — |
| `79cfe1` | concern-registry-and-generated-agents | — |
| `8a0644` | dispatch-plan-up-front | — |
| `ca8ba8` | review-corroboration-truth | — |
<!-- child-plans:end -->

Membership is the `<!-- epic: 33b1f9 -->` marker in each child `plan.md`; the table above is a generated
mirror that `New-Epic.ps1` rewrites. Run `Get-PlanState 33b1f9` for live rollup and the next unblocked
child plan.

## Decomposition notes

**Source.** Every child traces to evidence from `b0c0d3`: its 44-finding step 10.7 gate, its `/dr` round, the first real `/si` harvest, and the operator's `align:partial` acceptance. The clusters are catalogued in [review-system-enforcement-gaps.design.md](../../../design-notes/explorations/review-system-enforcement-gaps.design.md).

**Seam chosen: artifact contract, not lifecycle stage.** The operator's done bar names three stages (acquisition, implementation, learning loop), but "implementation" is not one seam — it is three artifacts with independent contracts: the evidence receipt, the review report, and the gates. Cutting on lifecycle alone would produce layer-per-plan, where no child delivers observable value until its siblings land. Cutting on artifact contract gives each child its own revertible surface.

**Why not one plan.** The queue spans ~8 Critical review findings, eight enforcement-gap clusters, three accepted `/si` candidates, six parked explorations and two `/dr` headline findings, across the review, receipt, ledger, install and CI surfaces. `b0c0d3` was smaller and still overran its advisory phase budget on 5 of 10 phases.

**Edges.** Only `cross-repo-si-and-standards` is blocked: it needs the durable proposal record from `learning-loop-durability` and correct consumer installs from `consumer-install-correctness` before a cross-repo protocol can rest on either. The remaining five children are parallel.

**Prior art reconciled.** *Reuses* plan `001`'s agent-safety rules and exit-code contract, and plan `002`'s receipt model, install confinement and hash verification. *Extends* `002`'s receipt concept to the evidence receipt — a different artifact sharing the same inability to describe a degraded run. No prior decision is superseded and none conflicts.

**Execution order.** Operator selected `gates-real-and-affordable` first: it shortens the feedback loop every later child is verified against.
