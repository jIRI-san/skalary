# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

- Current operator-selected finding: `docs/repository-maintenance.md`, `RCS-Epic-Archive-Link-Guard`.
- `docs/design-notes/architecture/plan-workflow.design.md:37-40` — completed epic archival and
  linked-source refusal expectation.
- `scripts/skalary/Archive-Epic.ps1:55-119` — current path checks, gates, confirmation, refresh, and
  move sequence.
- `scripts/skalary/New-Epic.ps1:400-404, 330-332, 73` — epic-file resolution and child-table write.
- `scripts/skalary/PlanState.psm1:1580-1628` — epic inventory reads the resolved `epic.md` path.
- `tests/skalary/ArchiveEpic.Tests.ps1` — existing archive, completion, collision, and `WhatIf` tests.
- Filtered historical index search (`Archive-Epic|epic archive|epic.md|symlink|reparse|linked source`):
  5 archived plan records matched requirement/risk/decision text and 0 intent candidates; 0 index
  errors. Matched records included `006`, `623cc2`, `768d7b`, `b0c0d3`, and `c21cdc`. No historical
  Markdown was loaded through the bounded consumer because no artifact was operator-selected; these
  index matches are leads, not confirmed intent or precedent.
