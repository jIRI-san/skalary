# Consistency Ledger

- [2026-08-01] A constant restated in prose needs either a pointer to the gated source or a test tying the two; an ungated third copy goes stale the moment the gated one moves. (plan-b0c0d3, src:autopilot, sev:Med) #phase-10 #req-17
- [2026-08-01] A gate whose scope is derived from what is already declared is self-referential; root the closed set in the grammar or state the residual bound where a reader will find it. (plan-b0c0d3, src:autopilot, sev:Med) #phase-10 #req-19
- [2026-08-01] A plugin payload edit must regenerate marketplace.json and registry.json in the same commit; the unit suite passes while the generated catalogs go stale. (plan-b0c0d3, src:autopilot, sev:Critical) #phase-10 #req-17
- [2026-08-09] Regenerated registry payload hashes after the final autopilot agent wording change. (plan-1936cb, src:autopilot, sev:Low) #maintainability-consistency #phase-5 #req-8
- [2026-08-10] Registry payload hashes are stale after final SI script and guide changes. (plan-1936cb, src:autopilot, sev:Med) #maintainability-consistency #phase-6 #req-8
- [2026-08-10] Second-opinion review found report-only wording obscured that a named structural eval is blocking typed evidence; clarified the boundary. (plan-1936cb, src:autopilot, sev:Med) #maintainability-consistency #phase-8 #req-8
- [2026-08-09] The autopilot design note retained the obsolete Add-LedgerEntry execution carve-out after installed phase harvest replaced it. (plan-1936cb, src:autopilot, sev:Med) #maintainability-consistency #phase-3 #req-7
- [2026-08-09] The harvester rejected writer-valid CrLog sources and the writer accepted hidden kind fields that could not be reconstructed for digest validation. (plan-1936cb, src:autopilot, sev:Med) #maintainability-consistency #phase-3 #req-4
