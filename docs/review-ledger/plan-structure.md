# Plan-Structure Ledger

- [2026-08-05] A ceiling derived from a mid-plan measurement cannot fail: bind it before any optimisation make it tightenable only and give the one escape hatch an absolute cap plus a written justification a test asserts. (plan-768d7b, src:autopilot, sev:High) #phase-1 #req-2
- [2026-08-05] A phase saving scored on wall clock is decided by scheduling noise when the move is small. Score a few-second move on the instrumented operation and keep wall clock for phases no single operation covers. (plan-768d7b, src:autopilot, sev:Med) #phase-2 #req-4
- [2026-08-28] dr legacy step 5.1 : complete gates and platform tier receipts must run after corpus rename on the exact migrated commit (plan-669ad3, src:autopilot, sev:Critical) #phase-2 #testing-evidence
- [2026-08-28] dr legacy step 5.2 : post-migration authority requires exactly four same-commit platform-tier receipts and fix-forward-only handling after a completed rename (plan-669ad3, src:autopilot, sev:Critical) #phase-3 #testing-evidence
- [2026-08-01] review: evidence markers cannot be satisfied by an autonomous run; plan them into the operator gate so an honest unrun is not mistaken for a failure. (plan-b0c0d3, src:autopilot, sev:Med) #phase-10 #req-17
