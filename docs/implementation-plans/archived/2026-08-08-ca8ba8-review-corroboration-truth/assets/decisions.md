# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Measure output similarity, not claimed serving identity.** A model cannot attest its own runtime identity, but suspiciously similar outputs are observable.
- **Suspicion can only lower confidence.** Near-identical nominally independent findings are flagged and excluded from corroboration or severity elevation.
- **State observable corroboration without overclaiming.** Reports say “corroborated, no suspicious similarity observed” and expose support, similarity, attendance, and elevation as separate dimensions; they never claim served-model independence.
- **Preserve independent discovery.** Rejected: feed model A's findings to model B; it destroys unanchored agreement and serializes the fanout.
- **Simplicity decision: extend the existing report.** Corroboration is engine-derived data on current findings and rendered views; review-run v1 remains the only freeze, publication, verification, cleanup, and retained-evidence lifecycle.
- **Use one conservative deterministic rule.** Compare normalized title/body/action within an existing merge group across distinct declared reviewers. Exact matches always flag; clearly near-duplicate text uses one documented high-similarity rule with a minimum-content guard. No embedding model, network call, package, policy descriptor, or version map is added.
- **Preserve raw findings and separate raw from effective severity.** Suspicious or degraded support cannot elevate severity, but it never removes or lowers the raw finding. Suspicion forces `needs-review`.
- **State only observable truth.** Reports expose support, attendance, similarity, and corroboration state and never claim served-model independence.
- **Derived fields are engine-owned.** Caller input cannot provide corroboration state or effective severity; order-independent collation computes them from retained raw findings and attendance.
- **Rejected as overengineered.** Review-run v2, policy/version maps, the 16,384-item scoring platform, child partitioning/admission, witness/digest commitments, dual readers, staged writer activation, and a second publication/receipt lifecycle are outside this plan.
- **Keep dependency on archived `c21cdc`.** Its review-run v1 implementation is the prior authority this plan extends; no active dependency is added.

## Prior-art reconciliation

- **Reuse `c21cdc` REQ-1/6/9/10, RISK-6, and D1/D2/D9/D10/D13/D14/D28.** Preserve frozen scope, manifest-last immutable authority, declared-model precision, lifecycle, artifact homes, and compact retained evidence.
- **Extend `c21cdc` RISK-7.** Replace declared-label unanimity with observable, bounded similarity evidence and a truthful elevation rule in v2.
- **Resolve `c21cdc` RISK-10 by versioned ownership.** `c21cdc` remains the complete v1 owner; this plan adds v2 and dual-version readers rather than independently rewriting attendance or persistence.
- **Reuse `863d97` decision “Keep review attendance separate.”** Marker/receipt truth remains outside review attendance and corroboration authority.
- **Reuse `34088e` REQ-6.** New contract descriptors remain owner-local, discoverable, and explicitly versioned.
- **Reuse `583308` typed-evidence decision.** Ordinary Pester remains the `test:` evidence host; workflow/review observations are not mislabeled as typed tests.

## Superseded design-review mechanics

- The prior v2 schema family, policy descriptor, exact 16,384 scoring envelope, admission partitioning, lifecycle activation, and retained commitment design are historical review output and not implementation instructions.
