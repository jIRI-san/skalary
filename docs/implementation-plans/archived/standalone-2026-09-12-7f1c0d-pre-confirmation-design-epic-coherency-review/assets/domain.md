# Domain Model

## Terms and meanings

- **Complete draft** — current plan assets and checklist after planning decisions are written but before final operator confirmation.
- **Planning review** — one read-only `secondary-model-high` pass over the complete draft.
- **Design lens** — architecture, feasibility, correctness, security, performance, and other concrete plan risks.
- **Epic-coherency lens** — compatibility of an epic child with epic intent, sibling ownership and interfaces, dependencies, sequencing, and already delivered behavior.
- **Applicability evaluation** — `primary-model-high` judgment over all findings using plan, epic, project, and implementation context.
- **Disposition** — an ephemeral recommendation to fix, simplify, defer, or ignore a finding.
- **Selected change** — a recommendation the operator authorizes `/cip` to apply to the current plan.

## Actors and boundaries

- The operator owns the final selection and planning confirmation.
- `/cip` owns orchestration, applicability presentation, and edits to the current plan.
- `secondary-model-high` is a read-only reviewer and does not decide plan scope.
- `primary-model-high` recommends dispositions but does not mutate the plan or replace operator judgment.
- `/dr` supplies review behavior and retained safety guards; it does not own planning state.
- `/ci` consumes the existing confirmed criteria and is outside this review interaction.

## Interfaces and ownership

- `plugins/create-implementation-plan/skills/cip/SKILL.md` owns checkpoint ordering and final confirmation.
- A concise CIP asset owns the detailed pre-confirmation review protocol so the entry skill stays small.
- `plugins/design-review/skills/dr/SKILL.md` owns read-only review semantics and the explicit planning-review role.
- Existing plan/epic resolvers and built-in read/search provide context; no new persistent context service is needed.
- Existing plugin manifests, sync scripts, and catalog writers own distribution.

## Invariants

- Review happens only after a complete draft and before `planning-confirmed`.
- Every finding is shown; none is automatically mandatory.
- Only operator-selected edits are applied.
- Epic design and coherency use one reviewer call, not two.
- The normal flow uses `secondary-model-high` followed by `primary-model-high`.
- Reviewer and evaluator failure stops visibly; no success-shaped fallback is produced.
- Review output never becomes a receipt, evidence authority, or hash-bound lifecycle state.
