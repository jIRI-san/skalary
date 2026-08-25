# Security Ledger

- [2026-08-01] A content stripper feeding a bootstrap or security gate must fail closed on malformed input; blanking the remainder turns an authoring slip into a silent gate bypass. (plan-b0c0d3, src:autopilot, sev:Med) #phase-10 #req-19
- [2026-08-05] A least-privilege assertion written as a denylist passes on contents-read plus checks-write and ignores job-level overrides. Assert the top-level block is exactly the scopes needed and reject job-level blocks. (plan-768d7b, src:autopilot, sev:Med) #phase-8 #req-9
- [2026-08-01] A machine-readable declaration is only worth its truth: assert the declared confine helper is shipped and called by the declaring unit or the manifest passes the gate while the gap stays open. (plan-b0c0d3, src:autopilot, sev:High) #phase-10 #req-19
- [2026-08-15] Include-rooted absence scans must enumerate hidden paths and reject reparse ancestors before trusting a clean result. (plan-cda9da, src:autopilot, sev:Med) #phase-4
- [2026-08-23] Registry prose rendered into instruction-position Markdown must reject every CommonMark block opener; single-line validation alone does not preserve template-owned structure. (plan-79cfe1, src:ci, sev:Med) #markdown #phase-3 #req-4 #security
- [2026-08-05] Removing -SkipPublisherCheck restores a check only if one still runs: Install-PSResource verifies nothing unless -AuthenticodeCheck is passed so the removal alone is a rename rather than a control. (plan-768d7b, src:autopilot, sev:High) #phase-8 #req-9

