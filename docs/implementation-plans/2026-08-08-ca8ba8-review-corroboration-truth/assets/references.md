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

- `plugins/code-review/skills/cr/assets/dispatch-guide.md` — declared/served analysis, Pro-tier
  degradation path, model roster.
- `scripts/skalary/Build-ReviewReport.ps1` — merge keys, elevation rule, header construction.
- `scripts/skalary/Test-ModelAllowlist.ps1` — validates declared models only.
- `tests/skalary/ReviewReportBundle.Tests.ps1` — asserts elevation when models agree.
- `docs/design-notes/explorations/review-system-enforcement-gaps.design.md` — the enforcement-gap
  clusters this epic decomposes.

## Settled boundary

This child depends on `c21cdc review-report-as-data`. `c21cdc` owns immutable v1 frozen-task/result
schemas, validation, persistence, derived attendance, and deterministic rendering. This child consumes
that boundary without rewriting it: existing v1 authority remains readable and unchanged, while new CR/DR
runs submit a raw result contract and publish an explicit engine-derived v2 authority. Served-model identity
remains unobservable; similarity is evidence against independence, while its absence is not identity proof.

## Cross-plan index consultation

Consulted on 2026-08-16 with:

`Get-PlanIndex.ps1 -Filter 'corroborat|review[- ]run|review evidence|model corroboration|finding corroboration' -Format Json`

- `c21cdc` — reuse its v1 authority/lifecycle records; extend RISK-7; resolve RISK-10 through explicit v2 ownership.
- `863d97` — reuse the decision that marker/receipt truth stays separate from review attendance.
- `34088e` — reuse REQ-6's owner-local, versioned contract descriptor pattern.
- `583308` — reuse the decision that ordinary Pester is the typed `test:` evidence host.
- `ca8ba8` — current epic-seeded records were treated as interview input, not prior art.

The index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`.
That error makes the generated index incomplete for the malformed entry; no corroboration overlap is known,
and this plan does not infer or reconstruct records from it.

## Design review round 1 decisions

- Fail-closed suspicious evidence is accepted even when malicious echo suppresses elevation; findings remain visible and never gain confidence.
- Suspicious-pair evidence is bounded by one deterministic witness per affected finding plus complete pair count/digest.
- Frozen v1 runs receive a completion bridge; all new freezes bind v2 publication and the policy digest.
- Admission partitioning is merge-group atomic, compact retained evidence carries v2 corroboration commitments, and rollout is reader-first.
- The complete lexical policy is a shipped schema-validated descriptor. Canonical authority records pair counts, not runtime timing.

## Design review round 2 decisions

- A single unpartitionable group produces permanent terminal admission@2 for that run id; identical replay remains exit 3.
- Reader-first deployment does not create v2 freezes. Activation changes new freeze and publish together; frozen runs always finish under their bound policy.
- Finalization retains raw and effective severity, and any suspicion forces `needs-review` rather than approval.
- Compact evidence uses aggregate commitments within the existing 8 KiB budget; raw input is retained as `review-result.<sha256>.json` and manifest role `rawResult`.
- The reachable two-model candidate ceiling is 16,384, derived from shared roster/finding limits.

## Design review round 3 decisions

- Policy@1 is exactly two-model and ASCII-tokenized; direct pure-gate evidence covers synthetic count 16,385 while envelope evidence covers reachable 16,384.
- Receipt@2 and terminal-status@2 expose engine-derived `needs-review`; caller approval is rejected and successful process exit remains 0.
- The existing worker ceiling applies to the aggregate parent operation across all children and rollup; both CI platforms must report evidence before finalization.
- Witnesses are derived identifiers/digests only, and retained evidence has a mandatory diagnosis floor within 8 KiB.
- The engine version map pins policy descriptor digests; v2 has its own limits parity owner and explicit canonical schema paths.

## Architecture and implementation context

- `docs/architecture-notes/arch-review-run-v1.md` — immutable v1 execution authority and retained-evidence boundary.
- `docs/design-notes/architecture/review-reporting.design.md` — review engine, schemas, rendering, lifecycle, distribution, and resource bounds.
- `docs/design-notes/architecture/plan-workflow.design.md` — typed evidence, retained review pairs, and plan finalization.
- `PSScriptAnalyzerSettings.psd1` — default PowerShell rules at Error/Warning severity with repository exclusions.
- `tools/suite-budget.psd1` — complete-suite platform ceilings; corroboration must not loosen them.
