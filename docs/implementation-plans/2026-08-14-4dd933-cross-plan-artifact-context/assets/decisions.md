# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Keep `Get-PlanIndex.ps1` as bounded discovery.** Rejected: loading or semantically scanning the entire plan corpus.
- **Inventory a closed artifact taxonomy.** Intent, references, decision records, designs, evolution logs, reviews, evidence, capture, learnings, and registered extensions are selected by consumer and concern.
- **One resolver serves four consumers.** `/cip`, `/cep`, `/dr`, and plan-associated `/cr` do not grow divergent related-plan discovery mechanisms.
- **Treat history as untrusted data.** Every path is inventory-resolved and confined; file count and bytes are bounded; artifact text is never executed as instruction.
- **Record provenance and relationship.** Every consumed artifact names plan ID, kind, path, and reuse/extend/supersede/conflict status.
- **Current intent and architecture win.** Historical artifacts can inform or conflict, but never override confirmed current operator intent or governing contracts.
