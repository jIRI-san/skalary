# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- Use the fast/slow split reserved by plan `768d7b` decision D13; do not use its ceiling-raise escape hatch.
- Keep `npm test` as Fast so local feedback, typed `test:` evidence, and the existing budget clock retain one meaning.
- Keep Slow mandatory in the same cross-platform CI matrix rather than scheduling it or making it advisory.
- Own membership in one tracked PowerShell data manifest; do not encode an expanding exclusion list independently in the runner, workflow, and tests.
- Keep the dedicated review-consumer install matrix outside both tiers because it already has its own blocking host and exit contract.
- Treat plan `1936cb` as unrelated; it remains parked.
- **REQ-4 review deferral (2026-08-17, operator-approved):** final CR run `a8b171b3-eeb7-428d-b805-93194f345606` retained Fast measurement-governance and Slow measurement-evidence findings. The operator explicitly approved `3.1`, directed that the Slow typed-measurement stall be resolved in a follow-up PR on `main`, and accepted merge without claiming the review was clean.
