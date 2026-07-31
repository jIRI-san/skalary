## Learnings Capture
Phase: 1

- [1.4] [trigger:reusable-pattern] Pester suites that Import-Module PlanState.psm1 -Force unload it from the calling session, so any crosscheck harness must parse all evidence markers before the first Invoke-Pester call; also, evidence test filters must anchor on the marker boundary or a substring test id (planstate- vs getplanstate-) inflates the case count.

## Learnings Capture
Phase: 2

- [2.1] [trigger:reusable-pattern] Structural guide tests must bind the documented contract to the script that produces it (gate section list <-> New-Plan scaffold), otherwise a rename silently disarms the gate.
- [2.3] [trigger:reusable-pattern] Any new plan.md parsing must read raw lines, not the fence-stripped copy, whenever the captured text is shown to a human or checked for content.

## Learnings Capture
Phase: 3

No entries for this phase.
