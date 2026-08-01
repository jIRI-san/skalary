# Error-Handling Ledger

- [2026-08-01] A first-use scaffold whose owner throws instead of creating the path disables the feature silently in every consumer repo; declare it only if the owner really writes it. (plan-b0c0d3, src:autopilot, sev:High) #phase-10 #req-19
- [2026-08-01] A payload that reads a file existing only in the source repo degrades silently rather than failing; every runtime read needs an install-time or first-use declaration. (plan-b0c0d3, src:autopilot, sev:High) #phase-10 #req-19

