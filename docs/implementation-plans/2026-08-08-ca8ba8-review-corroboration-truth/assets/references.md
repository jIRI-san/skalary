# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Where this came from

Operator comparison against a parallel implementation of the same ideas (2026-08-08). That
implementation claims two controls this repo lacks: near-identical findings from nominally
different models are flagged rather than counted as agreement, and the report header states the
corroboration behind findings and never downgrades it silently.

## Epic discussion provenance

- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 90-92 (2026-08-08): the operator selected the most valuable missing review controls; suspicious similarity and truthful corroboration were kept together as one control.
- The session explicitly rejected splitting measurement from reporting: a similarity detector nobody reports and a corroboration claim with no evidence are each incomplete.
- Epic `33b1f9` keeps this child independent of `8a0644` while requiring the two together to make review execution truthful.

## The gap

`plugins/code-review/skills/cr/assets/dispatch-guide.md` §"What the preflight cannot see" already
reasons about this, and closes the door:

> A subagent's model request is capped by the parent conversation's cost tier. A cheap orchestrator
> model silently collapses both reviewer passes onto that cheap model, with no error.
> Asking a reviewer to report its own model is worthless — a served model cannot attest its serving
> identity, so the report passes in exactly the case it exists to catch.
> This gap between declared and served is an **accepted, undetectable residual**.

The reasoning about self-reporting is sound and should stand. The conclusion that the gap is
undetectable does not follow: model identity is unobservable, but **output similarity is not**. Two
supposedly independent reviewers producing near-identical findings is the observable signature of
the collapse the guide describes.

## Why today's behaviour is worse than silence

`scripts/skalary/Build-ReviewReport.ps1` merges findings on exact `RootCause + Component` keys
(L157–L180) with no similarity comparison, and elevates severity when every dispatched model flags
an entry (L263). A collapse onto one model therefore does not merely go unnoticed — it **raises**
the report's confidence. The failure direction is inverted.

The header (L243–L244) states `Models: <roster>` and a dispatch count. Both describe the *declared*
configuration, which is exactly what the dispatch guide says cannot be trusted.

## Prior art

- [2026-08-22 simplification review](../../epics/2026-08-22-plan-simplification-review.md) — approved deriving corroboration in the existing report and rejected review-run v2, policy/version maps, large scoring/admission machinery, and a second publication lifecycle.
- `plugins/code-review/skills/cr/assets/dispatch-guide.md` — declared/served analysis, Pro-tier
  degradation path, model roster.
- `scripts/skalary/Build-ReviewReport.ps1` — merge keys, elevation rule, header construction.
- `scripts/skalary/Test-ModelAllowlist.ps1` — validates declared models only.
- `tests/skalary/ReviewReportBundle.Tests.ps1` — asserts elevation when models agree.
- `docs/design-notes/explorations/review-system-enforcement-gaps.design.md` — the enforcement-gap
  clusters this epic decomposes.

## Settled boundary

This child depends on archived `c21cdc review-report-as-data`. `c21cdc` owns review-run v1 frozen-task/result
schemas, validation, persistence, derived attendance, deterministic rendering, and retained evidence. This
child extends the existing report with engine-derived corroboration fields without replacing that lifecycle.
Served-model identity remains unobservable; similarity is evidence against independence, while its absence
is not identity proof.

## Cross-plan index consultation

Consulted on 2026-08-16 with:

`Get-PlanIndex.ps1 -Filter 'corroborat|review[- ]run|review evidence|model corroboration|finding corroboration' -Format Json`

- `c21cdc` — reuse and extend its v1 report and authority/lifecycle records; do not introduce v2 ownership.
- `863d97` — reuse the decision that marker/receipt truth stays separate from review attendance.
- `34088e` — reuse REQ-6's owner-local, versioned contract descriptor pattern.
- `583308` — reuse the decision that ordinary Pester is the typed `test:` evidence host.
- `ca8ba8` — current epic-seeded records were treated as interview input, not prior art.

The index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`.
That error makes the generated index incomplete for the malformed entry; no corroboration overlap is known,
and this plan does not infer or reconstruct records from it.

## Superseded design-review mechanics

- Review rounds 1-3 established useful invariants: suspicious support only lowers confidence, raw findings remain visible, raw/effective severity stay distinct, and similarity never proves model identity.
- Their v2 schema/lifecycle, policy descriptor, 16,384-item scoring envelope, partitioning/admission, witness commitments, and activation protocol are superseded by the simplicity decision.

## Architecture and implementation context

- `docs/architecture-notes/arch-review-run-v1.md` — immutable v1 execution authority and retained-evidence boundary.
- `docs/design-notes/architecture/review-reporting.design.md` — review engine, schemas, rendering, lifecycle, distribution, and resource bounds.
- `docs/design-notes/architecture/plan-workflow.design.md` — typed evidence, retained review pairs, and plan finalization.
- `PSScriptAnalyzerSettings.psd1` — default PowerShell rules at Error/Warning severity with repository exclusions.
- `tools/suite-budget.psd1` — complete-suite platform ceilings; corroboration must not loosen them.
