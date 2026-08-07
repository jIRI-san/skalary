# Error-Handling Ledger

- [2026-08-01] A first-use scaffold whose owner throws instead of creating the path disables the feature silently in every consumer repo; declare it only if the owner really writes it. (plan-b0c0d3, src:autopilot, sev:High) #phase-10 #req-19
- [2026-08-05] A gate measuring a command that spans several processes must read and clear its clock before every exit not only the green one: a clock stranded by a red run is charged to the next run as time it never spent. (plan-768d7b, src:autopilot, sev:High) #phase-4 #req-2
- [2026-08-01] A payload that reads a file existing only in the source repo degrades silently rather than failing; every runtime read needs an install-time or first-use declaration. (plan-b0c0d3, src:autopilot, sev:High) #phase-10 #req-19
- [2026-08-05] Under Set-StrictMode -Version Latest a missing config key read with dot notation is terminating and exits 1 the code reserved for tests failed. Name every field in the guard before reading any of them. (plan-768d7b, src:autopilot, sev:Med) #phase-4 #req-2

