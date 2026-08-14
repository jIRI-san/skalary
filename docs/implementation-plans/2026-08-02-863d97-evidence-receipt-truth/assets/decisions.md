# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Add an explicit skipped/degraded truth state.** Rejected: counting platform-skipped checks as passed or collapsing them into generic unrun output.
- **Keep one deterministic receipt grammar.** `/cip`, `/ci`, and autopilot consume the same formatter and cannot hand-author divergent lines.
- **The formatter remains format-only.** It renders verifier results and never reruns evidence, preserving separation between execution and receipt production.
- **Required proof fails closed.** Failed, stale, malformed, unrun, and unapproved skipped markers cannot satisfy finalization.
- **Keep review attendance separate.** This plan owns evidence-marker truth; `c21cdc` and `ca8ba8` own review-run and corroboration truth.
