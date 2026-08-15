# Performance Ledger

- [2026-08-01] A skill body is a recurring per-invocation context cost not a one-off; cap it and push reference detail into assets read on demand. (plan-b0c0d3, src:autopilot, sev:Med) #phase-10 #req-16
- [2026-08-15] Bound subprocess-heavy proof with an asserted launch cap and one shared kill timeout then measure through the existing platform suite budget. (plan-cda9da, src:autopilot, sev:Med) #phase-4
- [2026-08-05] Cases that spawn pwsh -NoProfile -File once or twice are paying for process startup not isolation. A fresh runspace over a cached InitialSessionState gives the clean session for ~1/20 the cost. (plan-768d7b, src:autopilot, sev:High) #phase-3 #req-4
- [2026-08-05] git clone <localpath> hardlinks the object store so copying a full clone per case replaces a cheap operation with N full byte copies. Shrink the fixture to a synthetic minimum before making it per-case. (plan-768d7b, src:autopilot, sev:High) #phase-2 #req-4

