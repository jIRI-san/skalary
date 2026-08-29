# Performance Ledger

- [2026-08-01] A skill body is a recurring per-invocation context cost not a one-off; cap it and push reference detail into assets read on demand. (plan-b0c0d3, src:autopilot, sev:Med) #phase-10 #req-16
- [2026-08-09] Active-directory discovery materialized unbounded file lists before starting the scan deadline and enforcing plus-one limits. (plan-1936cb, src:autopilot, sev:Med) #performance #phase-4 #req-7
- [2026-08-10] Batch writers must index idempotence and recurrence keys once; per-candidate scans become quadratic at the legal final-sweep boundary. (plan-1936cb, src:autopilot, sev:Med) #performance #phase-3 #req-4
- [2026-08-15] Bound subprocess-heavy proof with an asserted launch cap and one shared kill timeout then measure through the existing platform suite budget. (plan-cda9da, src:autopilot, sev:Med) #phase-4
- [2026-08-05] Cases that spawn pwsh -NoProfile -File once or twice are paying for process startup not isolation. A fresh runspace over a cached InitialSessionState gives the clean session for ~1/20 the cost. (plan-768d7b, src:autopilot, sev:High) #phase-3 #req-4
- [2026-08-10] Code review found no significant defect in the indexed ledger batch engine or capacity-result ordering. (plan-1936cb, src:autopilot, sev:Low) #performance #phase-3 #req-4
- [2026-08-10] Final CR: ledger batch idempotence and recurrence are O N times M at the 10000-record and 4096-candidate boundary. (plan-1936cb, src:autopilot, sev:Critical) #performance #phase-3 #req-4
- [2026-08-09] Fixed ls-tree and ls-remote collection allocating unbounded hostile output before applying plus-one limits. (plan-1936cb, src:autopilot, sev:Med) #performance #phase-5 #req-7
- [2026-08-05] git clone <localpath> hardlinks the object store so copying a full clone per case replaces a cheap operation with N full byte copies. Shrink the fixture to a synthetic minimum before making it per-case. (plan-768d7b, src:autopilot, sev:High) #phase-2 #req-4
- [2026-08-29] Phase admission performed two state scans per workflow iteration; fixed by one Get-PlanState JSON invocation reused for state and admission. (plan-6a629b, src:autopilot, sev:Med) #performance #phase-1 #req-1
- [2026-08-29] Planning-context confinement repeatedly resolved every inventory path physically; fixed by logical identity prefilter before physical validation. (plan-6a629b, src:autopilot, sev:Med) #performance #phase-1 #req-1
- [2026-08-29] review 40a86ef6 finding 2 deferred: whole-overflow rescans predate phase 1 and require a separate indexed overflow design without weakening existing validation (plan-6a629b, src:autopilot, sev:Med) #performance #phase-1
- [2026-08-29] review 40a86ef6 finding 4 fixed: Get-PlanState builds one inventory and returns the complete admission result (plan-6a629b, src:autopilot, sev:Med) #performance #phase-1 #req-1
- [2026-08-10] Second-opinion review confirmed indexed batch semantics plan caching and capacity status ordering are behavior-preserving. (plan-1936cb, src:autopilot, sev:Low) #performance #phase-3 #req-4
- [2026-08-29] SI starts a Git process for each pinned blob; deferred as pre-existing because a safe cat-file batch transport is a separate bounded-reader design. (plan-6a629b, src:autopilot, sev:Med) #performance #phase-1 #req-6
