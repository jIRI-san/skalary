# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **GitHub first, provider-neutral core.** The first live adapter targets GitHub Projects v2 and issues; the domain model leaves an Azure DevOps extension seam without claiming live ADO support.
- **Support new and existing hierarchy nodes.** Synchronization can create, link, or extend remote epics/features/items instead of requiring an empty project.
- **Local plans remain authoritative.** Remote work items mirror goals, purpose, acceptance criteria, dependencies, and status; they do not replace local plan assets or canonical IDs.
- **Persist stable mappings and reconcile idempotently.** Repeated runs update known items and fail loud on ambiguous or conflicting links rather than duplicating or guessing.
- **Avoid destructive remote convergence.** Operator edits and provider state are reported as conflicts unless an explicit policy owns the update.
