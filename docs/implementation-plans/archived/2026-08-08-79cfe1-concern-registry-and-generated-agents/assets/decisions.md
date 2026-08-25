# Decisions

<!-- Key decisions made during planning — one bullet per decision. -->

- **Simplicity decision: one source, one generator, one drift check.** `tools/review-concerns.json` and one shared template generate the CR/DR concern agents and mappings; the deterministic `-WhatIf` test proves convergence.
- **Preserve settled policy.** The seven ids, their meanings, model-agnostic agents, explicit-model dispatch, injection guards, read-only stance, and concern-to-ledger totality remain unchanged.
- **Generate whole agents and mapping views.** Common structure stays template-owned; bounded registry fields provide shared guidance and explicit CR/DR variants. A registry that drives nothing remains rejected.
- **Use existing writers for downstream state.** `Sync-PluginScripts.ps1`, `Sync-Dogfood.ps1`, plugin version handling, `Build-Marketplace.ps1`, and `Build-Registry.ps1` keep their current ownership and sequencing.
- **No review-run contract change.** This is build-time authorship only; `ARCH-Review-Run-V1`, frozen task truth, dispatch, publication, and retained evidence remain unchanged.
- **Rejected as overengineered.** Generated-inventory authority, Git-bound migration provenance, marker-adoption state, custom multi-plugin locking/transactions, version-first recovery protocol, dogfood prune/recovery authority, new gate families, and dedicated Fast/Slow orchestration are not required for deterministic generation.
- **No dependencies or new packages.** Existing PowerShell, Pester, sync, and validation infrastructure is sufficient.
- **Final review disposition (2026-08-23).** The operator selected Wrap after three capped plan-finalization CR cycles. Current-HEAD `review:cr` and `review:dr` re-verification is explicitly deferred for REQ-1, REQ-2, REQ-3, and REQ-4: the phase-3 CR was clean and the phase-scoped DR completed, every later CR finding was fixed with focused coverage, and the final build/test gate passed, but no fourth CR or new DR may be represented as clean evidence.
