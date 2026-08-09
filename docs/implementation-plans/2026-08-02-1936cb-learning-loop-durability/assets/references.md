# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

- Epic `33b1f9` — success signals require phase-wide ledger accumulation and a durable `/si` proposal/decline record; non-goals preserve autopilot safety and defer cross-repo use.
- `docs/design-notes/explorations/review-system-enforcement-gaps.design.md` — Cluster F and G1–G3 are the direct source: no `si-due` trace, final-phase-only ledger promotion, silent feedback/learning loss, and harvest commands that did not run.
- `docs/design-notes/architecture/self-improvement.design.md` — current `/pfb`/`/si` separation, untrusted-input contract, write-scope gate, draft-PR-only behavior, and headless skip policy.
- `docs/design-notes/architecture/plan-workflow.design.md` — script-only mutation, layout resolution, phase capture, finalization harvest, ledger idempotence, plugin bundling, and epic boundaries.
- `docs/design-notes/architecture/autopilot-execution.design.md` — canonical headless finalization flow and the rule that autopilot never runs `/si`.
- Plan `b0c0d3` (archived) — reuse REQ-10 concern mapping, REQ-13 queued-feedback precedent, REQ-14 `/si` safety controls, REQ-19 scaffold declarations, and REQ-20 layout resolution; extend them with durable SI state and executable harvest resolution.
- Plan `007` (archived) — reuse the durable ledger taxonomy, `Add-LedgerEntry` idempotence/locking, phase provenance tags, and script-only append contract; extend write timing from finalization-only to phase crosscheck plus retry sweep.
- Plan `768d7b` (archived) — gate runtime is already resolved and must not be reopened here; use its deterministic/full-gate contract for final proof.
- Plan `2366ad` (active child) — owns cross-repo `/si` and standards transport after this state contract and consumer-install correctness land.
- Current implementation surfaces: `plugins/autopilot/agents/autopilot.agent.md`, `plugins/continue-implementation/skills/ci/assets/{crosscheck-guide,execution-guide}.md`, `plugins/self-improvement/skills/si/**`, `scripts/skalary/{Add-LedgerEntry,Add-WorkflowNote,Update-FeedbackQueue}.ps1`, and their bundled/dogfood copies.
- Design review on 2026-08-09 — retained substantive findings on lifecycle ordering, behavioral evidence, distribution ownership, crash recovery, untrusted reads, phase provenance, bounded costs, operability, candidate-set completeness, branch authority, trusted-base scope enforcement, and dependency/sync timing. Rejected only the claim that the repository-standard Assets index can override trusted review scope.
- State topology decision — [decisions/si-state-topology.md](decisions/si-state-topology.md) defines authoritative merge semantics, run/manifest write ordering, deterministic correlation PRs, and partial-failure recovery.
- Prior-art index command: `scripts/skalary/Get-PlanIndex.ps1 -Format Markdown -Filter 'self-improvement|learning|ledger|feedback|harvest|receipt'` (active + archived corpus, deterministic).
