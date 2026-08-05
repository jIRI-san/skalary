# Security Ledger

- [2026-08-01] A content stripper feeding a bootstrap or security gate must fail closed on malformed input; blanking the remainder turns an authoring slip into a silent gate bypass. (plan-b0c0d3, src:autopilot, sev:Med) #phase-10 #req-19
- [2026-08-05] A least-privilege assertion written as a denylist passes on contents-read plus checks-write and ignores job-level overrides. Assert the top-level block is exactly the scopes needed and reject job-level blocks. (plan-768d7b, src:autopilot, sev:Med) #phase-8 #req-9
- [2026-08-01] A machine-readable declaration is only worth its truth: assert the declared confine helper is shipped and called by the declaring unit or the manifest passes the gate while the gap stays open. (plan-b0c0d3, src:autopilot, sev:High) #phase-10 #req-19
- [2026-08-05] Removing -SkipPublisherCheck restores a check only if one still runs: Install-PSResource verifies nothing unless -AuthenticodeCheck is passed so the removal alone is a rename rather than a control. (plan-768d7b, src:autopilot, sev:High) #phase-8 #req-9

