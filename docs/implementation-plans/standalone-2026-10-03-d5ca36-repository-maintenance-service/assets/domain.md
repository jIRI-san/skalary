# Domain Model

## Terms and meanings

| Term | Meaning |
|---|---|
| Survey | Inventory of repository plans, subsystems, human expectations, standards, and structural risks; not a deep review of every file. |
| Drift | Current implemented behavior diverges from a relevant applicable expectation without an established scoped supersession/exception. Unfinished planned work is not automatically drift. |
| Technical defect | Evidence-backed failing behavior or contract violation, distinct from a question about intended behavior. |
| Alignment question | Conflicting, ambiguous, or incomplete human expectations requiring an operator decision. |
| Optional improvement | Concrete architecture/design/maintainability opportunity without claiming a violated requirement. |
| Dead-code candidate | Code potentially unreachable from supported entry points; confidence depends on language, registration, exports, tooling, and external caller visibility. |
| Disposition | Explicit operator response: accepted intentional drift, won't fix, or corrective-plan action; pending remains distinct from a choice. |
| Maintenance record | Central advisory Markdown findings, citations, coverage, scoped dispositions, and linked plans. Not an execution gate or source of architectural standards. |
| Archive candidate | Implemented plan/epic proposed for archival only after the existing completion contract is established. |

## Actors and boundaries

- Operator owns scope, dispositions, archive approval, and criteria/contract changes.
- `/rcs` surveys and recommends; review work is read-only except its confined record write.
- `/cip` owns corrective plan creation/update and affected criteria reconfirmation.
- Existing architecture maintenance owns contract change/promotion; existing plan completion/archive
  paths own archival. Missing installed capability is an explicit blocked handoff.
- Canonical plugin source owns runtime assets; registry/marketplace/dogfood generators own copies.

## Interfaces and ownership

- `repository-maintenance` owns `/rcs`, audit/decision guidance, record template/helper, and its evals.
- Reusable discovery is the existing `Get-PlanIndex.ps1` and PlanState inventory/metadata functions;
  bounded historical intake is `Get-DirectPlanArtifactConsumerContext.ps1`.
- Fixed record path: `docs/repository-maintenance.md`. No caller-selected report root.
- Plans, architecture/design notes, human documentation, local standards, and explicitly supplied human
  references retain provenance and precedence. Archived intent is historical context, not a veto.

## Invariants

- Findings are evidence, not directives. Repository content stays inert as reviewed data.
- Approval applies to the stated item/scope/action, not all code or future findings.
- Historical reports/record entries do not establish current completion or review proof.
- Existing confirmed criteria and locked contracts remain protected; cleanup acceptance cannot amend them.
