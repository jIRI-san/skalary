# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turn 0: the operator said to drop architecture tests because they are unused and currently overkill.
- Epic `bcece1` Goal and Prior art reconciliation narrow the retirement to the architecture-tests plugin, runner, receipts, adapters, and `arch:` evidence while preserving architecture notes and ADRs.
- Prior plan `21f21d` established the architecture-notes and architecture-tests surfaces; `768d7b` decision D11 later found `arch:` unsatisfiable for a real plan.
- `docs/design-notes/architecture/architecture-notes.design.md` and `docs/design-notes/architecture/architecture-tests.design.md` define the preserve/remove boundary.

## Prior-art index reconciliation (2026-08-15)

`Get-PlanIndex.ps1 -Filter 'architecture[- ]tests?|arch:|architecture receipt|fitness function|lock gate' -Format Json` returned three plans, eight requirements, three risks, twelve decision rows, and no indexing errors.

- **Supersedes `21f21d` REQ-8 through REQ-11, REQ-14, and REQ-17.** Those records created the plugin, adapters/providers, semantic layer, `arch:` marker, fixtures, and freshness receipts that this plan removes because the repo never adopted a usable check/config/receipt path.
- **Reuses `21f21d` REQ-15.** The architecture-notes tier and deliberate two-index loading remain.
- **Extends `768d7b` D11.** Its real-plan proof dropped one unsatisfiable `arch:` criterion; this plan removes the unused runtime contract that made the marker unsatisfiable.
- The index emitted empty text for unnumbered historical decision bullets. The relationships above use the indexed requirement records plus the epic's preserved, dated prior-art provenance; no conflicting prior record was found.

## Current-state observations

- No active plan requirement uses `arch:`; matches are confined to archived plan `21f21d` and historical transcripts/reports.
- No `arch-test-config.json` or `docs/architecture-notes/receipts/` tree exists.
- Both live contracts are prose-only and `provisional`; neither carries runner fields, so schema simplification needs no contract-data migration.
- `Remove-Plugin.ps1` is receipt-driven, but explicit removal does not satisfy the operator's automatic-cleanup requirement; the retirement protocol is therefore owned here as a narrow generic registry capability.

## Ledger consultation

- `security.md`: machine-readable declarations must be exercised by the declaring unit; tombstone/source confinement tests must prove the cleanup control is real.
- `error-handling.md`: missing consumer assets and malformed config must fail loud; retirement states and remedies are closed and actionable.
- `testing.md`: inventory assertions need negative mutations; retirement and historical-boundary fixtures prove the checks are non-blind.
- `consistency.md`: plugin changes regenerate registry and marketplace in the same step.
- `plan-structure.md`: no `review:` marker is used because this autonomous plan has no human gate.
- `observability.md`: every degraded/source-mismatch outcome names the residue and explicit remedy.

## Design review round 1 reconciliation

Run `c7e47a7f-7aba-4bfd-b8f4-b5c02e6ac5dd` completed 14/14 reviewer invocations across Claude Opus 5 and GPT-5.6 Sol. The plan adopted its corroborated findings on consumer-fixture ownership, indexed residue cost, green sequencing, one removal engine, install confinement, source identity/redaction, result semantics, journal recovery, append-only tombstones, mixed-marker tokenization, old-installer delivery, exact test ownership, direct retired targets, runtime measurement, rollback records, include-rooted scans, preview activation, mixed-version handling, root-scaffold residue, and exact schema/gate paths.

Operator decisions after the review:

- Keep `locked` with a runner-independent canonical contract digest.
- Require a persisted non-destructive preview before automatic cleanup can apply.
- Block an unrelated operation only after a rollback-complete reconciliation failure; do not add a bypass.

Findings about imperative prose in the plan and DR dispatch wrapper were rejected as uncorroborated review-boundary false positives. The generic-retirement complexity concern was resolved by recording the operator's explicit automatic-cleanup requirement and constraining it through one shared engine and preview-first activation.

## Design review round 2 reconciliation

Run `2e924941-4d5d-4ff6-9c0e-1eb6eb99df6a` completed 14/14 invocations. The plan adopted its actionable findings by freezing old-installer and historical fixtures before mutation; moving all evaluator imports before module deletion; proving the generic catalog mechanism before first use; assigning all deletion-coupled tests/evals/profile/docs to the atomic tombstone step; adding always-on lock authority; using one explicit CI baseline blob; validating untrusted journals and state paths; defining preview refusal/retry/recovery/bootstrap exits; preserving complete state while bounding output; naming design-note ownership; limiting process tests; using existing suite budgets; adding seeded-red scans; excluding tombstones from the Copilot marketplace; and adding exact `34088e` consumption evidence.

The repeated workflow-prose injection finding remained an uncorroborated false positive and required no plan change.

## Design review round 3 reconciliation

Run `3c8e9a73-5f88-411c-b71e-8a783550da0d` completed 14/14 invocations. The plan adopted all actionable findings: exact `34088e` fixture consumption, exhaustive outcomes, sole design-note deletion ownership, honest reviewer-enforced human promotion, tokenization before deletion, explicit `registry-ci.yml`/gate-inventory wiring, same-commit schema/eval synchronization, per-file historical rehashing, tombstone-pinned deletion authority/manual residue, first-publication semantics, stale-preview refresh, approval-key reporting, separate irreversible publication phase, globally bounded residue replay, state-path reconfinement, one canonical digest helper, and corrected requirement mappings.

The repeated normal-prose injection finding remained an uncorroborated false positive. No known plan issue remains after the third default review round.
