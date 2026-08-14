# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Split harvest from proposal.** Consumer-side free-text collection gets a narrow write scope and emits a typed artifact; proposal runs in an upstream-rooted workspace under upstream rules.
- **Always produce the interchange artifact.** Same-repo and cross-repo runs use one path so proposal and decline history exists by construction.
- **Large proposals become plans.** Rejected: a new free-form autopilot mode for `/si`. Large changes run `/cip` in the upstream checkout and use normal plan/autopilot controls.
- **Treat cross-repo evidence as a claim.** It cannot be verified against absent consumer records, so upstream re-judgment and promotion criteria remain required.
- **Unresolved for `/cip`:** transport and credential policy must choose among a local upstream branch, explicit push, or a manual handoff without silently expanding phase-1 privilege.
