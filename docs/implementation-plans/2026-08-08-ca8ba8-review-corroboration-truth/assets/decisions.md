# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Measure output similarity, not claimed serving identity.** A model cannot attest its own runtime identity, but suspiciously similar outputs are observable.
- **Suspicion can only lower confidence.** Near-identical nominally independent findings are flagged and excluded from corroboration or severity elevation.
- **State the corroboration regime explicitly.** Reports distinguish independently corroborated, single-source, suspicious, and degraded findings from the declared model roster.
- **Preserve independent discovery.** Rejected: feed model A's findings to model B; it destroys unanchored agreement and serializes the fanout.
- **Keep report-shape ownership with `c21cdc`.** This plan extends its machine-readable envelope with corroboration semantics rather than independently redesigning `Build-ReviewReport.ps1`.
