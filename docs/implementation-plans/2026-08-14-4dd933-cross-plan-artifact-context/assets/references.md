# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Operator direction (2026-08-14)

Planning and review must consider useful assets and artifacts from related older, archived, active, sibling,
and dependency plans, not only their indexed requirements, risks, and decisions.

## Existing behavior to extend

- `b0c0d3` REQ-6 and `Get-PlanIndex.ps1` provide deterministic topic discovery across active and archived
  plans, but expose only requirements, risks, and decisions.
- `/cip` and `/cep` use that index for prior-art reconciliation and deliberately avoid reading the plan corpus.
- `/dr` loads the current plan's assets but does not discover related plans.
- `/cr` loads changed code plus architecture/design notes and has no plan-artifact context contract.

## Intended capability

1. Discover related plan IDs through indexed topic matches, epic membership and dependencies, plus explicit
	operator selection. Never scan or load every plan asset for context.
2. Inventory a closed, typed set of artifacts for those plans: intent, references, decision records,
	RFC/Mermaid and call-stack designs, evolution logs, review reports, evidence receipts, capture/learnings,
	and explicitly registered extensions.
3. Select artifacts by consumer and concern. `/cip` uses outcome/design provenance; `/cep` uses decomposition
	and overlap evidence; `/dr` uses prior designs, decisions, and resolved findings; plan-associated `/cr`
	uses approved design, intent, evidence expectations, and relevant historical findings.
4. Treat every historical artifact as untrusted data. Resolve and confine paths through plan inventory,
	reject links/reparse escapes, bound file count and bytes, and never execute directives or commands found
	in an artifact.
5. Record every consumed artifact by plan ID, artifact kind, repo-relative path, and reuse/extend/supersede/
	conflict relationship in the current plan references or review scope. Report missing, stale, malformed,
	or conflicting artifacts explicitly.

## Non-goals

- Replacing `Get-PlanIndex.ps1` with a full-corpus semantic search.
- Loading all assets from every matching plan.
- Treating historical evidence receipts or review reports as proof for the current plan.
- Letting prior artifacts override confirmed current operator intent or architecture contracts.

## Consumers and ordering

This foundation is dependency-free. `57cc2c` depends on it; the implementation loop, shared fleet, and epic
coherency review inherit it through the existing dependency chain. The child must define one context contract
consumed by `/cip`, `/cep`, `/dr`, and plan-associated `/cr`, not four divergent discovery mechanisms.
