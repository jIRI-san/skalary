# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

- Epic `33b1f9` — success signals require phase-wide ledger accumulation and a durable `/si` proposal/decline record; non-goals preserve autopilot safety and defer cross-repo use.
- `docs/design-notes/explorations/review-system-enforcement-gaps.design.md` — Cluster F and G1–G3 are the direct source: no `si-due` trace, final-phase-only ledger promotion, silent feedback/learning loss, and harvest commands that did not run.
- `docs/design-notes/architecture/self-improvement.design.md` — current `/pfb`/`/si` separation, untrusted-input contract, write-scope gate, draft-PR-only behavior, and headless skip policy.
- `docs/design-notes/architecture/plan-workflow.design.md` — script-only mutation, layout resolution, phase capture, finalization harvest, ledger idempotence, plugin bundling, and epic boundaries.
- `docs/design-notes/architecture/autopilot-execution.design.md` — canonical headless finalization flow and the rule that autopilot never runs `/si`.
- [2026-08-22 simplification review](../../epics/2026-08-22-plan-simplification-review.md) — approved direction to retain existing capture/ledger files and add only a small append-only due/result record.
- Plan `b0c0d3` (archived) — reuse REQ-10 concern mapping, REQ-13 queued-feedback precedent, REQ-14 `/si` safety controls, REQ-19 scaffold declarations, and REQ-20 layout resolution; extend them with durable SI state and executable harvest resolution.
- Plan `007` (archived) — reuse the durable ledger taxonomy, `Add-LedgerEntry` idempotence/locking, phase provenance tags, and script-only append contract; extend write timing from finalization-only to phase crosscheck plus retry sweep.
- Plan `768d7b` (archived) — gate runtime is already resolved and must not be reopened here; use its deterministic/full-gate contract for final proof.
- Plan `2366ad` (active child) — owns cross-repo learning transport and consumes this plan's durable local records.
- Current implementation surfaces: `plugins/autopilot/agents/autopilot.agent.md`, `plugins/continue-implementation/skills/ci/assets/{crosscheck-guide,execution-guide}.md`, `plugins/self-improvement/skills/si/**`, `scripts/skalary/{Add-LedgerEntry,Add-WorkflowNote,Update-FeedbackQueue}.ps1`, and their bundled/dogfood copies.
- Design review on 2026-08-09 — retained useful rationale on non-blocking headless behavior, untrusted reads, phase provenance, distribution ownership, and replay safety. Its state topology, merge-authority, exhaustive recovery, and bounded-platform recommendations are superseded by the simplicity decision.
- Prior-art index command: `scripts/skalary/Get-PlanIndex.ps1 -Format Markdown -Filter 'self-improvement|learning|ledger|feedback|harvest|receipt'` (active + archived corpus, deterministic).
