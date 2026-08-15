# Design Review Evolution

## Round 1 — 2026-08-15

**Issues found:** 104 findings. One unsupported prompt-injection claim was retained in the published review artifact and rejected. The remaining findings clustered around retirement sequencing, fixture ownership, probe attendance/isolation, scanner migration, filesystem races, limit ownership, folder-stable dependency evidence, runtime budgets, diagnostics, and authoritative platform attestations.

**Issues fixed:** Added hard `34088e -> cda9da` and `8a0644 -> 34088e` decisions; narrowed retirement to consumer transition deltas; selected the production installer and one shared fixture substrate; defined schema-backed one-process-per-plugin probes, exact attendance, zero skips, canaries, deadlines, and bounded reports; staged scanner enumerate/disposition/enforce; selected parent-identity mutation rechecks; named owner-local limit descriptors and compatibility; replaced folder evidence with resolver-backed graph tests; added early 10s/30s/60s runtime allocations and a blocking integration-tier fallback; required current-tree Linux/Windows CI attestations.

**Operator decisions:** Hard retirement and fleet dependencies; fresh CI receipts for both platforms; parent identity recheck rather than native handle-relative no-follow; blocking integration tier rather than reduced coverage or a ceiling raise.

**Deferred residual:** Handle-relative no-follow mutation primitives remain outside this plan after reparse-ancestor rejection and immediate parent-identity verification.