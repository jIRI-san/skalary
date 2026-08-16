# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- Use the fast/slow split reserved by plan `768d7b` decision D13; do not use its ceiling-raise escape hatch.
- Keep `npm test` as Fast so local feedback, typed `test:` evidence, and the existing budget clock retain one meaning.
- Keep Slow mandatory in the same cross-platform CI matrix rather than scheduling it or making it advisory.
- Own membership in one tracked PowerShell data manifest; do not encode an expanding exclusion list independently in the runner, workflow, and tests.
- Keep the dedicated review-consumer install matrix outside both tiers because it already has its own blocking host and exit contract.
- Treat plan `1936cb` as unrelated; it remains parked.
- **Operator finalization decision (2026-08-16):** do not run another `review:cr` for this recovery because this feature has already received repeated review. Defer only REQ-4's `review:cr` marker without claiming it passed; retain the green deterministic partition, runner, workflow, Fast, and Slow evidence as the completion authority.
