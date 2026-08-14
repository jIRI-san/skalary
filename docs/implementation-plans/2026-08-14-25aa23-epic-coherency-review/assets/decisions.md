# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Review the accepted cut before finalization.** The operator still confirms the proposed cut first; coherency review then tests it independently before child drafting proceeds.
- **Review epic shape, not child implementation.** Goal coverage, verticality, ownership, overlap, dependencies, prior art, MVP, and complete outcome are in scope; child requirements and code design remain with `/cip` and `/dr`.
- **Reuse the shared fleet.** Epic review follows `8a0644`'s four-in-flight cap, waves, attendance, and degradation contract instead of adding another scheduler.
- **Decision-changing findings return to the operator.** Clear defects revise the cut; agent review never silently overrides an accepted product boundary.
- **Record a verdict.** Finalization requires inspectable review outcome and finding disposition, not only transient chat feedback.
