# Decisions

<!-- Key decisions made during planning — one bullet per decision. Historical detailed decision files are retained as review history; this file records the executable direction. -->

- **Simplicity decision: extend the current evidence pipeline.** Existing marker verifiers produce richer result objects, `Build-EvidenceReceipt.ps1` formats them, and `Test-Plan -Stage PlanCrosscheck` remains the finalization gate.
- **Use one explicit outcome vocabulary.** Passed, failed, skipped, unrun, stale, degraded, and waived remain visible from execution through the receipt; only passed and exact waived evidence satisfy a required marker.
- **Keep waivers plan-local and small.** `assets/evidence-waivers.json` is optional and validated when read. No approval service, policy digest, audit lifecycle, or repository-wide waiver registry is added.
- **Extend the ordinary test runner.** Focused Pester selection and structured output reuse current discovery, process, timeout, environment, and exit behavior rather than creating another executor or exit-code family.
- **Preserve current authority boundaries.** File/review/test producers execute checks; the formatter never reruns them; review attendance remains owned by review-run v1.
- **Rejected as overengineered.** Whole-tree digest projection, CAS/UUID receipt publication, dormant v2 migration and cutover, new schemas/modules for a parallel receipt system, new exit ranges, GitHub API CI-proof authority, and exhaustive limit matrices are outside this plan. The historical `evidence-truth-contract.md` is superseded where it describes those mechanisms.
- **No active dependency is required.** The change applies to the current surviving marker vocabulary without owning architecture-test retirement.
