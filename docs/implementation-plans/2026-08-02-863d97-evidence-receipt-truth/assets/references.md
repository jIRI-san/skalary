# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Epic `33b1f9` goal: receipts and reports must reflect what actually ran and distinguish degraded runs from clean ones.
- Session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 24-40 and 49-52: the `b0c0d3` gate exposed partial-run, skipped-evidence, and report-truth gaps that were decomposed into this epic.
- `docs/design-notes/explorations/review-system-enforcement-gaps.design.md`, Cluster B: the remaining open row is explicit evidence `skipped` state, assigned to `863d97`.
- `docs/design-notes/architecture/plan-workflow.design.md`: current shared receipt grammar and formatter-only boundary.
