# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Retire architecture tests, not architecture knowledge.** The architecture-notes tier, human review, and ADR lifecycle remain; executable test machinery is removed.
- **Remove the full runtime contract coherently.** Plugin, adapters, runner, schemas, config, receipts, tests, distribution entries, and documentation are one retirement surface.
- **Retire `arch:` evidence.** Plans and validators must not claim architecture evidence backed by a subsystem the repo no longer uses.
- **Prefer deletion over replacement.** Rejected: introducing another semantic architecture enforcement framework in this plan.
- **Preserve active architectural decisions.** Existing notes and provisional contracts remain available to planning and review even after their test adapters disappear.
