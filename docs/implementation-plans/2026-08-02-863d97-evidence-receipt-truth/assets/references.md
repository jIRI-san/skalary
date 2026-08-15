# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Epic `33b1f9` goal: receipts and reports must reflect what actually ran and distinguish degraded runs from clean ones.
- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 24-40 and 49-52: the `b0c0d3` gate exposed partial-run, skipped-evidence, and report-truth gaps that were decomposed into this epic.
- `docs/design-notes/explorations/review-system-enforcement-gaps.design.md`, Cluster B: the remaining open row is explicit evidence `skipped` state, assigned to `863d97`.
- `docs/design-notes/architecture/plan-workflow.design.md`: current shared receipt grammar and formatter-only boundary.

## Prior-art reconciliation

Generated with `Get-PlanIndex.ps1` using receipt/status-specific filters; the index returned no errors.

- **Reuse `7645b1` REQ-10 and its shared-receipt decision.** Keep one format-only builder, one golden line grammar, full commit binding, one line per marker, and all-markers requirement aggregation. This plan extends the input/result vocabulary and adds a deterministic persisted gate; it does not re-litigate formatter ownership.
- **Reuse `b0c0d3` REQ-20 and its plan-layout decision.** Evidence receipts and the new optional policy resolve through the current assets/legacy layout boundary; existing or archived plans are not migrated.
- **Extend `768d7b` RISK-4.** That plan explicitly deferred the evidence `skipped` state to `863d97`; this plan supplies the structured runner, status/disposition contract, and gate that close the handoff.
- **Reuse the `c21cdc` boundary.** Review-run attendance, task outcomes, and valid-degraded publication remain owned by review-run v1; this plan normalizes only the final `review:` marker result and does not mutate review-run semantics.
- **Compatible with `21f21d` pure-parse precedent.** Persisted evidence is parsed, never executed, at the archival gate; architecture-test receipt details are outside this plan and are not copied into the evidence grammar.

No prior record is superseded and no conflict remains.

## Active cross-epic dependency

- **Depend on `cda9da` architecture-test retirement.** Round 3 found that synchronizing architecture-tests or consuming `Get-ArchGateOutcome` here conflicts with that active plan's removal contract. `863d97` now executes after `cda9da`, consumes only the surviving post-retirement marker vocabulary, and does not recreate retired runtime evidence machinery.
