# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Session `e64afe83-10c6-427c-bc6c-9a51069bea14`, turn 0: the operator requested whole GitHub/Azure DevOps hierarchies for epics, features, backlog items, goals, purpose, and acceptance criteria, including extending existing remote work.
- Epic `bcece1` chooses GitHub as the first live provider and an Azure DevOps-extensible model as the non-live seam.
- Dependency `57cc2c`: supplies confirmed goals, user outcomes, and acceptance intent for remote hierarchy content.

## Prior-art reconciliation

- **Extends `57cc2c` REQ-1 and RISK-1.** Their scaffold rows contain no substantive content; this plan supplies typed evidence and concrete remote-system risks.
- **Reuses `57cc2c` D1 and D2.** The complete synchronization outcome is planned as installable MVP-first vertical increments, not an API-layer sequence.
- **Reuses `57cc2c` D3 and D4.** Confirmed operator meaning and Epic discussion provenance remain durable in intent, decisions, references, and capture.
- **Extends `57cc2c` D5.** `assets/decisions/program-design.md` approves the projection/diff/admission/apply/store shape before implementation.
- **Reuses `57cc2c` D6.** Contract, user-experience, security, and irreversible remote-mutation uncertainty blocked drafting until resolved.
- **Extends `25aa23` REQ-3 and D11.** That plan remains sole owner of `Resolve-EpicAssetPath`; after dependency completion this plan adds one `WorkHierarchySync` kind rather than introducing another epic path resolver. Its epic inventory, round-trip, and confinement rules are reused unchanged.
- The topic-specific index query returned no other prior GitHub hierarchy requirement, risk, or decision. `9fda0b` itself is current work, not prior art.
- The index reported `docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement: no plan.md`. The operator accepted this disclosed, unrelated gap; its untracked review residue was not modified.

## Implementation references

- `docs/implementation-plans/epics/2026-08-14-bcece1-intent-to-delivery-vertical-workflow/epic.md` — child ownership and non-goals.
- `docs/design-notes/architecture/plan-workflow.design.md` — plan/epic identity, progress, layout, evidence, and parser ownership.
- `docs/design-notes/architecture/process-pr-comments.design.md` — ambient `gh`, REST/GraphQL, pagination, marker, rate-limit, and token-safe precedent; reused through policy parity rather than runtime coupling.
- `docs/design-notes/architecture/plugin-registry.design.md` — plugin ownership, scaffolds, installed dependencies, dogfood/registry distribution, and analyzer gates.
- GitHub REST API, “Sub-issues” (consulted 2026-08-21) — list/add/remove/reprioritize APIs, same-owner condition, status/error shapes, and `2026-03-10` API version.
- GitHub Projects v2 API documentation (consulted 2026-08-21) — organization project lookup, field/option IDs, `addProjectV2ItemById`, and `updateProjectV2ItemFieldValue`.
- DR round 1 run `eaa8e878-a9c4-4e95-8d55-25ea7d92edc5` — clean 14/14 attendance; 36 findings drove the hardened runtime contracts.
