Plan b0c0d3 Crosscheck:
✓ REQ-1 — file:plugins/create-implementation-plan/skills/cip/assets/plan-template.md#contains:assets/intent.md — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-1 — file:.github/skills/cip/assets/plan-template.md#contains:assets/ — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-1 — test:plan-assets-template-shape — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-1 — test:new-plan-scaffolds-assets — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — file:scripts/skalary/PlanState.psm1#contains:function Resolve-PlanSection — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:planstate-dual-layout-parity — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:planstate-resolver-both-present — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:planstate-divergence-ignores-cosmetic-drift — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:planstate-asset-fences-stripped — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:planstate-resolver-empty-fails-loud — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:planstate-resolver-malformed-fails-loud — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:planstate-legacy-layout-unchanged — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-2 — test:getplanstate-dual-layout-parity — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-3 — file:plugins/continue-implementation/skills/ci/SKILL.md#contains:assets/ — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-3 — test:ci-loads-assets-on-demand — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-3 — test:migration-is-atomic — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-3 — test:migrated-plan-validates — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-4 — file:plugins/create-implementation-plan/skills/cip/assets/interview-guide.md#contains:intent — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-4 — file:plugins/create-implementation-plan/skills/cip/assets/intent-template.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-4 — test:cip-intent-gate — passed: 8 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-4 — test:ci-reads-intent — passed: 5 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-5 — file:scripts/skalary/Test-Plan.ps1#contains:human-step-detail — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-5 — test:human-step-detail-gate-fails — passed: 4 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-5 — test:human-step-detail-gate-passes — passed: 9 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-5 — test:ci-human-handoff-detail — passed: 6 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-6 — file:scripts/skalary/Get-PlanIndex.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-6 — file:plugins/create-implementation-plan/skills/cip/assets/interview-guide.md#contains:Get-PlanIndex — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-6 — test:planindex-covers-archived — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-6 — test:planindex-deterministic — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-7 — file:scripts/skalary/Test-ModelAllowlist.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-7 — file:tools/model-allowlist.psd1#contains:claude-opus-5 — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-7 — test:model-allowlist-rejects-unknown — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-7 — test:model-allowlist-rejects-qualified-name-on-cli-agent — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-7 — test:model-allowlist-fails-on-unmapped-agent — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-7 — test:model-allowlist-covers-autopilot-config — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-7 — test:no-gemini-references — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-8 — file:plugins/code-review/agents/cr-security.agent.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-8 — file:plugins/code-review/agents/cr-performance.agent.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-8 — file:plugins/design-review/agents/dr-security.agent.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-8 — test:concern-agents-complete — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-8 — test:concern-agents-carry-injection-guard — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-8 — test:legacy-model-agents-removed — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-9 — file:plugins/code-review/skills/cr/assets/dispatch-guide.md#contains:28 — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-9 — test:dispatch-guide-scaling-thresholds — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-9 — test:dispatch-budget-reported — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-9 — test:declared-model-preflight-fails-loud — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-9 — review:dr — passed: /dr at step 10.7, 7 concerns x 2 models, 36 findings, 18 cross-model corroborated — 9b2034bb5ac5a24ac48ef7ba6a7ed47b15580afb
✓ REQ-10 — file:plugins/code-review/skills/cr/assets/concern-ledger-map.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-10 — file:plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md#contains:concern-ledger-map — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-10 — test:concern-ledger-map-total — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-11 — file:plugins/code-review/agents/scripts/Get-ReviewScope.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-11 — file:plugins/code-review/plugin.json#contains:Get-ReviewScope.ps1 — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-11 — test:review-scope-modes — passed: 16 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-11 — test:no-diff-extraction-refs — passed: 6 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-12 — file:plugins/code-review/skills/cr/SKILL.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-12 — file:plugins/design-review/skills/dr/SKILL.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-12 — file:plugins/code-review/agents/cr.agent.md#contains:skills/cr/SKILL.md — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-12 — test:cr-dr-skill-shim-parity — passed: 5 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-12 — test:prompts-are-thin-shortcuts — passed: 4 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-13 — file:plugins/self-improvement/skills/pfb/SKILL.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-13 — file:plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md#contains:pfb — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-13 — test:pfb-queues-marker-under-autopilot — passed: 6 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-13 — test:pfb-consumes-queued-marker — passed: 8 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — file:plugins/self-improvement/skills/si/SKILL.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — file:plugins/self-improvement/skills/si/assets/harvest-guide.md#contains:UNTRUSTED_INPUT — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — file:scripts/skalary/Test-SiWriteScope.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — test:si-wraps-harvested-sources — passed: 5 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — test:si-write-scope-denies-workflows — passed: 4 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — test:si-write-scope-catches-untracked — passed: 5 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — test:si-write-scope-rejects-symlink-escape — passed: 5 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — test:si-proposes-never-merges — passed: 3 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-14 — test:si-offered-at-completion — passed: 3 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-15 — file:plugins/create-implementation-plan/skills/cep/SKILL.md#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-15 — file:scripts/skalary/New-Epic.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-15 — test:epic-scaffold-links-children — passed: 9 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-15 — test:ci-selects-next-child-plan — passed: 9 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-16 — file:scripts/skalary/Test-SkillSize.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-16 — test:skill-size-cap-enforced — passed: 3 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-16 — test:skills-under-cap — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-17 — file:docs/design-notes/architecture/plan-workflow.design.md#contains:assets/ — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-17 — file:docs/design-notes/project/copilot-customizations.design.md#contains:concern — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-17 — test:design-note-drops-orchestrator-fence — passed: 4 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-17 — test:unit — passed: 703 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-17 — test:validate-all — passed: scripts/validate.ps1 exited 0 — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-17 — review:cr — passed: cr branch at step 10.7, 7 concerns x 2 models, 14 of 28 invocations, 44 findings, 3 fixed — 9b2034bb5ac5a24ac48ef7ba6a7ed47b15580afb
✓ REQ-18 — file:scripts/skalary/Build-ReviewReport.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-18 — file:plugins/code-review/skills/cr/scripts/Build-ReviewReport.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-18 — file:plugins/design-review/skills/dr/scripts/Build-ReviewReport.ps1#exists — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-18 — test:build-reviewreport-merge-dedup — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-18 — test:build-reviewreport-severity-elevation — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-18 — test:build-reviewreport-deterministic — passed: 3 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — file:schemas/plugin/plugin.schema.json#contains:scaffolds — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — file:schemas/registry/registry.schema.json#contains:scaffolds — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — test:asset-refs-declared-in-files — passed: 10 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — test:scanner-grammar-ignores-fenced-examples — passed: 4 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — test:asset-bootstrap-drift-whatif — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — test:scaffolds-reach-registry — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — test:scaffold-literal-mode — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-19 — test:scaffold-parameterized-mode-confined — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-20 — file:scripts/skalary/Add-WorkflowNote.ps1#contains:Resolve-PlanAssetPath — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-20 — file:scripts/skalary/PlanState.psm1#contains:function Resolve-PlanAssetPath — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-20 — test:workflownote-dual-layout — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-20 — test:evidence-receipt-dual-layout — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-20 — test:no-split-brain-after-migration — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-21 — file:scripts/skalary/Test-Plan.ps1#contains:phase-budget-points — passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-21 — test:phase-budget-marker-honored — passed: 1 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
✓ REQ-21 — test:phase-budget-defaults-to-6 — passed: 2 case(s) passed — 8151e61ca3fe09267a1473bcec36e91d1a90b0ce
