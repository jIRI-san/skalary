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
that published v1 artifact to detect near-identical output and decide corroboration/elevation policy. It
does not rewrite v1 in place: any additional persisted evidence or semantic change introduces an explicit
v2 plus migration. Served-model identity remains unobservable; similarity is evidence, not identity proof.
