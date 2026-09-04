# Ownership inventory

Plan `2aa7ec` step 1.1 snapshot, taken from tracked repository content on 2026-09-03. This is a human-owned Markdown inventory, not a schema or validation interface.

## Discovery rules

- **Gate:** one row per active blocking/support invocation in the two tracked `.github/workflows/*.yml` hosts, plus each gate invoked only by `scripts/validate.ps1`. Identity is `host :: gate/invocation`. The excluded LLM tier is not active.
- **JSON:** every tracked `*.json`, excluding archived implementation plans, generated review-run artifacts under active plan `assets/reviews/`, and `*.json.example`. A path may also have an architecture-contract row because the JSON file and its logical contract are separate ownership decisions.
- **Test:** every tracked `*.Tests.ps1`, including plugin eval tests. Helpers and fixtures with other suffixes are not tests in this category.
- **Design note:** every tracked Markdown record under `docs/design-notes/`, including `.design-notes.md`.
- **Architecture contract:** the active architecture index, three non-staging architecture notes, three logical `ARCH-*` declarations, and `architecture-contract.schema.json`.

## Explicit exclusions

- JSON excludes 66 files under `docs/implementation-plans/archived/`, one generated active-plan review receipt, and five tracked `*.json.example` files. Gitignored runtime trees such as `artifacts/`, `.eval-artifacts/`, and live review-run directories are untracked and outside the inventory.
- Gate discovery excludes checkout, dependency installation, artifact upload, summaries, notification, and `Invoke-ContainerToolchainGate.ps1 -Mode Initialize` setup. `gate:llm-eval` is explicitly excluded, not active.
- Architecture discovery excludes `.staging/ADR-HARVEST.md` and generated `architecture.human.md`.
- `tests/CiWorkflow.psm1` and `scripts/skalary/Invoke-ContainerToolchainGate.ps1` are workflow support, not a sixth category; their removal is named in gate reasons. Their three `*.Tests.ps1` companions remain Test rows.

## Counts

| Category | Count | Keep | Transfer | Delete | Uncertain |
|---|---:|---:|---:|---:|---:|
| Gate | 23 | 2 | 4 | 17 | 0 |
| JSON | 111 | 5 | 97 | 9 | 0 |
| Test | 124 | 24 | 93 | 7 | 0 |
| Design note | 28 | 10 | 18 | 0 | 0 |
| Architecture contract | 8 | 3 | 4 | 1 | 0 |

**Total category rows:** 294. Rows are counted by category; the four architecture JSON files intentionally also appear as contract/schema decisions.

**Coverage arithmetic:** 267 unique file paths across JSON, tests, notes, and architecture records; 16 workflow-hosted gate/support invocations; and 7 `validate.ps1`-only gate invocations. The four architecture JSON overlaps bring the category-row total to 294.

## Items

Closed vocabularies: `Owner` is one of `2aa7ec`, `367e9a`, `3a4498`, `623cc2`; `Disposition` is `keep`, `transfer`, `delete`, or baseline-test-only `uncertain`. `Value category` is required only for retained tests and is exactly `current user behavior`, `external format`, or `high-impact regression`. `—` means not applicable.

| Category | Item | Owner | Disposition | Value category | Reason | External consumer |
|---|---|---|---|---|---|---|
| Gate | `registry-ci.yml :: gate:script-analyzer` | `2aa7ec` | `delete` | — | Hosted analyzer step ends with registry-ci.yml; tests/CiWorkflow.psm1 and tests/skalary/Ci.Tests.ps1 are workflow-only support. | — |
| Gate | `registry-ci.yml :: gate:review-schema-capability` | `2aa7ec` | `delete` | — | Hosted preflight ends with registry-ci.yml; 367e9a owns review capability outside this invocation. | — |
| Gate | `registry-ci.yml :: gate:structural-evals` | `2aa7ec` | `delete` | — | Hosted npm eval invocation ends; focused local eval commands remain available. | — |
| Gate | `registry-ci.yml :: support:suite-budget-clock` | `2aa7ec` | `delete` | — | Workflow-spanning budget clock has no local-first role and its CiGates workflow assertions are deleted. | — |
| Gate | `registry-ci.yml :: gate:plan-validation` | `2aa7ec` | `delete` | — | Hosted plan sweep ends; 367e9a owns focused plan validation. | — |
| Gate | `registry-ci.yml :: gate:repository-validation` | `2aa7ec` | `delete` | — | Hosted whole-repository wrapper ends with registry-ci.yml and tests/skalary/CiGates.Tests.ps1. | — |
| Gate | `registry-ci.yml :: gate:plugin-retirement-history` | `2aa7ec` | `delete` | — | Event-SHA history check depends on GitHub Actions; 623cc2 owns any local lifecycle replacement. | — |
| Gate | `registry-ci.yml :: gate:unit-suite` | `2aa7ec` | `delete` | — | Routine hosted whole Fast tier conflicts with explicit focused local validation. | — |
| Gate | `registry-ci.yml :: gate:slow-suite` | `2aa7ec` | `delete` | — | Routine hosted Slow tier conflicts with the operator-only full-suite path. | — |
| Gate | `registry-ci.yml :: gate:review-consumer-install` | `2aa7ec` | `delete` | — | Hosted matrix invocation ends; 367e9a owns focused review-install evidence. | — |
| Gate | `registry-ci.yml :: gate:registry-validation` | `2aa7ec` | `delete` | — | Hosted registry step ends; 623cc2 owns focused lifecycle checks. | — |
| Gate | `registry-ci.yml :: gate:dogfood-drift` | `2aa7ec` | `delete` | — | Hosted dogfood drift step ends; 623cc2 owns install-surface consistency. | — |
| Gate | `registry-ci.yml :: gate:generated-output-drift` | `2aa7ec` | `delete` | — | Hosted generated-file assertion ends; 623cc2 owns registry generation policy. | — |
| Gate | `autopilot-container-ci.yml :: gate:container-relevance` | `2aa7ec` | `delete` | — | Post-merge detector ends with scripts/skalary/Invoke-ContainerToolchainGate.ps1 and its gate tests. | — |
| Gate | `autopilot-container-ci.yml :: gate:container-image` | `2aa7ec` | `delete` | — | Hosted image measurement ends; tests/skalary/AutopilotContainerGate.Tests.ps1 is workflow-only. | — |
| Gate | `autopilot-container-ci.yml :: gate:container-result` | `2aa7ec` | `delete` | — | Hosted receipt verification ends; tests/skalary/AutopilotContainerGate.Tests.ps1 is workflow-only. | — |
| Gate | `scripts/validate.ps1 :: gate:plugin-script-bundles` | `623cc2` | `transfer` | — | Plugin bundle drift belongs with install and update lifecycle. | — |
| Gate | `scripts/validate.ps1 :: gate:marketplace-drift` | `623cc2` | `transfer` | — | Marketplace generation belongs with registry and marketplace lifecycle. | — |
| Gate | `scripts/validate.ps1 :: gate:model-allowlist` | `2aa7ec` | `keep` | — | Retain as a local shared agent-configuration check pending focused-runner integration. | — |
| Gate | `scripts/validate.ps1 :: gate:skill-size` | `2aa7ec` | `keep` | — | Retain as a local shared instruction-size check pending focused-runner integration. | — |
| Gate | `scripts/validate.ps1 :: gate:plan-draft-validation` | `367e9a` | `transfer` | — | Plan-state validation belongs with CIP, CI, and plan execution. | — |
| Gate | `scripts/validate.ps1 :: gate:arch-doc-freshness` | `623cc2` | `transfer` | — | Temporary compatibility check for the transferred legacy JSON contracts; remove after the owning children convert them. | — |
| Gate | `scripts/validate.ps1 :: gate:architecture-contract-integrity` | `2aa7ec` | `delete` | — | Schema-and-digest enforcement is internal permanent machinery; preserve contracts in readable Markdown. | — |
| JSON | `.autopilot.json` | `367e9a` | `transfer` | — | Internal autopilot config transfers for conversion or deletion; it is not an external format. | — |
| JSON | `.github/plugin/marketplace.json` | `623cc2` | `transfer` | — | Child owns this published catalog or marketplace format and its consumers. | GitHub Copilot CLI marketplace loader |
| JSON | `.github/skills/architecture-notes/assets/schemas/architecture-contract.schema.json` | `2aa7ec` | `delete` | — | Internal architecture schema has no external consumer; replace schema-bound contracts with readable Markdown. | — |
| JSON | `.github/skills/autopilot/devcontainer/devcontainer.json` | `367e9a` | `transfer` | — | Internal autopilot configuration transfers to `367e9a`; current execution uses `docker build`. | — |
| JSON | `.github/skills/autopilot/schemas/autopilot.host.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/autopilot/schemas/autopilot.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/cr/assets/review-standards.json` | `367e9a` | `transfer` | — | Internal review standards data transfers with CR/DR for readable-format disposition. | — |
| JSON | `.github/skills/cr/scripts/schemas/review/review-admission.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/cr/scripts/schemas/review/review-limits.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/cr/scripts/schemas/review/review-manifest.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/cr/scripts/schemas/review/review-plan.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/cr/scripts/schemas/review/review-run.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/cr/scripts/schemas/review/terminal-status.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/dr/assets/review-standards.json` | `367e9a` | `transfer` | — | Internal review standards data transfers with CR/DR for readable-format disposition. | — |
| JSON | `.github/skills/dr/scripts/schemas/review/review-admission.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/dr/scripts/schemas/review/review-limits.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/dr/scripts/schemas/review/review-manifest.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/dr/scripts/schemas/review/review-plan.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/dr/scripts/schemas/review/review-run.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/dr/scripts/schemas/review/terminal-status.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/si/schemas/cross-repo-export.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/si/schemas/manifest.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/si/schemas/repair-observation.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/si/schemas/repair-receipt.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/si/schemas/resolver-receipt.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.github/skills/si/schemas/run.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `.vscode/settings.json` | `2aa7ec` | `keep` | — | Workspace settings are a VS Code-owned external format. | VS Code |
| JSON | `docs/self-improvement/state.json` | `3a4498` | `transfer` | — | Internal SI state transfers for conversion or deletion; it is not an external format. | — |
| JSON | `package.json` | `2aa7ec` | `keep` | — | Package scripts and metadata are consumed by npm. | npm |
| JSON | `plugins/architecture-notes/plugin.json` | `2aa7ec` | `keep` | — | Plugin manifest is required by the Copilot plugin loader. | GitHub Copilot plugin loader |
| JSON | `plugins/architecture-notes/skills/architecture-notes/assets/schemas/architecture-contract.schema.json` | `2aa7ec` | `delete` | — | Internal architecture schema has no external consumer; replace schema-bound contracts with readable Markdown. | — |
| JSON | `plugins/autopilot/devcontainer/devcontainer.json` | `367e9a` | `transfer` | — | Internal autopilot configuration transfers to `367e9a`; current execution uses `docker build`. | — |
| JSON | `plugins/autopilot/plugin.json` | `367e9a` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `plugins/autopilot/schemas/autopilot.host.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/autopilot/schemas/autopilot.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/code-review/plugin.json` | `367e9a` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `plugins/code-review/skills/cr/assets/review-standards.json` | `367e9a` | `transfer` | — | Internal review standards data transfers with CR/DR for readable-format disposition. | — |
| JSON | `plugins/code-review/skills/cr/scripts/schemas/review/review-admission.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/code-review/skills/cr/scripts/schemas/review/review-limits.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/code-review/skills/cr/scripts/schemas/review/review-manifest.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/code-review/skills/cr/scripts/schemas/review/review-plan.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/code-review/skills/cr/scripts/schemas/review/review-run.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/code-review/skills/cr/scripts/schemas/review/terminal-status.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/continue-implementation/evals/waza/fixtures/atomic-step/package.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `plugins/continue-implementation/plugin.json` | `367e9a` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `plugins/create-implementation-plan/plugin.json` | `367e9a` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `plugins/design-notes/plugin.json` | `2aa7ec` | `keep` | — | Plugin manifest is required by the Copilot plugin loader. | GitHub Copilot plugin loader |
| JSON | `plugins/design-review/plugin.json` | `367e9a` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `plugins/design-review/skills/dr/assets/review-standards.json` | `367e9a` | `transfer` | — | Internal review standards data transfers with CR/DR for readable-format disposition. | — |
| JSON | `plugins/design-review/skills/dr/scripts/schemas/review/review-admission.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/design-review/skills/dr/scripts/schemas/review/review-limits.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/design-review/skills/dr/scripts/schemas/review/review-manifest.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/design-review/skills/dr/scripts/schemas/review/review-plan.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/design-review/skills/dr/scripts/schemas/review/review-run.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/design-review/skills/dr/scripts/schemas/review/terminal-status.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/plugin-manager/plugin.json` | `623cc2` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `plugins/process-pr-comments/plugin.json` | `2aa7ec` | `keep` | — | Plugin manifest is required by the Copilot plugin loader. | GitHub Copilot plugin loader |
| JSON | `plugins/self-improvement/plugin.json` | `3a4498` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `plugins/self-improvement/schemas/cross-repo-export.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/self-improvement/schemas/manifest.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/self-improvement/schemas/repair-observation.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/self-improvement/schemas/repair-receipt.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/self-improvement/schemas/resolver-receipt.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/self-improvement/schemas/run.schema.json` | `3a4498` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `plugins/work-hierarchy-sync/plugin.json` | `367e9a` | `transfer` | — | Child owns this plugin manifest and must retain it only while the Copilot plugin loader consumes it. | GitHub Copilot plugin loader |
| JSON | `registry-retirements.json` | `623cc2` | `transfer` | — | Internal retirement catalog transfers with the repository lifecycle scripts that consume it. | — |
| JSON | `registry.json` | `623cc2` | `transfer` | — | Child owns this published catalog or marketplace format and its consumers. | Skalary installer and registry clients |
| JSON | `schemas/architecture/ARCH-Eval-Gate-Separation.json` | `2aa7ec` | `delete` | — | Internal architecture contract JSON has no external consumer; preserve its logical contract in Markdown. | — |
| JSON | `schemas/architecture/ARCH-Install-Confinement.json` | `623cc2` | `transfer` | — | Internal subsystem JSON transfers to its canonical child for conversion, retention, or deletion. | — |
| JSON | `schemas/architecture/ARCH-Review-Run-V1.json` | `367e9a` | `transfer` | — | Internal subsystem JSON transfers to its canonical child for conversion, retention, or deletion. | — |
| JSON | `schemas/architecture/architecture-contract.schema.json` | `2aa7ec` | `delete` | — | Internal architecture schema has no external consumer; replace schema-bound contracts with readable Markdown. | — |
| JSON | `schemas/eval-case/eval-case.schema.json` | `2aa7ec` | `delete` | — | Internal eval-case schema has no external consumer; keep readable eval guidance instead. | — |
| JSON | `schemas/marketplace/marketplace.schema.json` | `623cc2` | `transfer` | — | Internal marketplace validation schema transfers for conversion or deletion; it is not external. | — |
| JSON | `schemas/plugin/plugin.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/receipt/receipt.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/registry/plugin-retirement.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/registry/registry.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/retirement/removal-journal.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/retirement/retirement-state.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/review/review-admission.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/review/review-concerns.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/review/review-limits.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/review/review-manifest.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/review/review-plan.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/review/review-run.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `schemas/review/terminal-status.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/approval/keys.json` | `623cc2` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/fixture-manifest.json` | `623cc2` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/installed-payload/architecture-tests/assets/schemas/arch-test-config.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/installed-payload/architecture-tests/assets/schemas/arch-test-receipt.schema.json` | `623cc2` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/manifest/plugin.json` | `623cc2` | `transfer` | — | Internal frozen fixture transfers with the architecture-retirement baseline test that consumes it. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/manifest/scaffolds.json` | `623cc2` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/receipt/architecture-tests.json` | `623cc2` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/registry/architecture-tests.json` | `623cc2` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/plugin-retirement/cda9da-historical-manifest.json` | `623cc2` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/corpus/gate-10.7-cr-branch.legacy-projection.golden.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/corpus/gate-10.7-cr-branch.plan.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/corpus/gate-10.7-cr-branch.provenance.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/corpus/gate-10.7-cr-branch.run.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/corpus/new-layout.expectation.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/corroboration-matrix.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/edge/always-reject.schema.json` | `367e9a` | `transfer` | — | Internal schema transfers with its subsystem for conversion or deletion; it is not classified as external. | — |
| JSON | `tests/skalary/fixtures/review-run/edge/cases.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/edge/maximum-envelope.spec.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/review-run/secrets/allow-block-corpus.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tests/skalary/fixtures/work-hierarchy/projection.golden.json` | `367e9a` | `transfer` | — | Internal test fixture transfers with the subsystem tests that consume it. | — |
| JSON | `tools/review-concerns.json` | `367e9a` | `transfer` | — | Internal subsystem JSON transfers to its canonical child for conversion, retention, or deletion. | — |
| JSON | `tools/structural-eval-required.json` | `2aa7ec` | `delete` | — | Internal structural-eval roster has no external consumer; fold required cases into readable runner guidance. | — |
| JSON | `tools/suite-coverage-baseline.json` | `2aa7ec` | `delete` | — | Internal suite profile/runtime/coverage data supports machinery being removed. | — |
| JSON | `tools/suite-profile.json` | `2aa7ec` | `delete` | — | Internal suite profile/runtime/coverage data supports machinery being removed. | — |
| JSON | `tools/suite-runtime.json` | `2aa7ec` | `delete` | — | Internal suite profile/runtime/coverage data supports machinery being removed. | — |
| Test | `plugins/architecture-notes/evals/architecture-notes.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `plugins/autopilot/evals/autopilot.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `plugins/code-review/evals/cr.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `plugins/continue-implementation/evals/ci.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `plugins/create-implementation-plan/evals/cip.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `plugins/design-notes/evals/design-notes.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `plugins/design-review/evals/dr.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `plugins/plugin-manager/evals/plugin-manager.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `plugins/process-pr-comments/evals/pprc.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `plugins/self-improvement/evals/self-improvement.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/CompletionResume.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/ContainerOffline.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/EpicAutopilot.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/ModelConfiguration.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/PreparePackages.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/RebundleLoop.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/Resolve-HostCommand.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/SandboxOffline.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/autopilot/TimeoutConfiguration.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/evals/EvalTools.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/InvokeWazaEvals.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/LegacyCutover.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/ProbeGhEntitlement.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/ResolveToken.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/TestEvalsRequired.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/WazaArchitectureNotesConvention.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/WazaAutopilotConvention.Tests.ps1` | `367e9a` | `transfer` | — | Autopilot convention coverage transfers with execution ownership. | — |
| Test | `tests/evals/WazaCiConvention.Tests.ps1` | `367e9a` | `transfer` | — | CI convention coverage transfers with the CI workflow skill. | — |
| Test | `tests/evals/WazaCipConvention.Tests.ps1` | `367e9a` | `transfer` | — | CIP convention coverage transfers with plan creation. | — |
| Test | `tests/evals/WazaCrConvention.Tests.ps1` | `367e9a` | `transfer` | — | CR convention coverage transfers with review execution. | — |
| Test | `tests/evals/WazaDesignNotesConvention.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/evals/WazaDrConvention.Tests.ps1` | `367e9a` | `transfer` | — | DR convention coverage transfers with review execution. | — |
| Test | `tests/evals/WazaPluginManagerConvention.Tests.ps1` | `623cc2` | `transfer` | — | Plugin-manager convention coverage transfers with lifecycle tooling. | — |
| Test | `tests/evals/WazaProcessPrCommentsConvention.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/pprc/GitHubPr.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/skalary/Add-LedgerEntry.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Add-WorkflowNote.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ArchEvidence.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ArchitectureRetirementBaseline.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ArchitectureTestRetirement.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/AssetBootstrap.Tests.ps1` | `367e9a` | `transfer` | — | Plan-asset bootstrap coverage transfers with plan execution. | — |
| Test | `tests/skalary/AutopilotContainer.Tests.ps1` | `367e9a` | `transfer` | — | Container execution coverage transfers with autopilot ownership. | — |
| Test | `tests/skalary/AutopilotContainerGate.Tests.ps1` | `2aa7ec` | `delete` | — | Post-merge container assertions disappear with Invoke-ContainerToolchainGate.ps1. | — |
| Test | `tests/skalary/Bootstrap.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Build-EvidenceReceipt.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/BuildRegistryCollation.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Ci.Tests.ps1` | `2aa7ec` | `delete` | — | Workflow-shape assertions disappear with registry-ci.yml. | — |
| Test | `tests/skalary/CiGates.Tests.ps1` | `2aa7ec` | `delete` | — | Workflow gate-inventory assertions disappear with both workflow hosts and CiWorkflow.psm1. | — |
| Test | `tests/skalary/ConcernAgents.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ConsumerInstall.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/CrossRepoSi.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Dependency.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/DesignNotes.Tests.ps1` | `2aa7ec` | `keep` | external format | Protects a file contract consumed by Copilot customization tooling. | — |
| Test | `tests/skalary/DiffExtractionRetired.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/DispatchGuide.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Epic.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/EpicCoherency.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/EvidenceTruth.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/FeedbackQueue.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/FleetDispatch.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Get-PlanState.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/HumanStepDetail.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/LearningHarvest.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/LearningLoop.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Marketplace.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Migrate-PlanFolderPrefixes.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ModelAllowlist.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Prevents host-incompatible model bindings from breaking agent execution; prune to the small core host-format and runtime-binding cases. | — |
| Test | `tests/skalary/New-Plan.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PayloadScope.Tests.ps1` | `2aa7ec` | `keep` | high-impact regression | Protects shared runner confinement, discovery, or execution from broad breakage. | — |
| Test | `tests/skalary/PhaseReceiptMigration.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PlanArtifactContext.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PlanAssets.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PlanIndex.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PlanIntent.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PlanState.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PlanningContext.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PluginRetirement.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PluginScriptBundle.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/PromptShortcuts.Tests.ps1` | `2aa7ec` | `keep` | current user behavior | Protects an unaffected plugin or focused local command users invoke today. | — |
| Test | `tests/skalary/Remove-LedgerEntry.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Repair-Plans.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewConcerns.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewConsumerInstall.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewCorroboration.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewCycleGate.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewReportBundle.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewReportCorpus.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewReportDiscovery.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunArtifacts.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunBudget.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunEncoding.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunEpicGraph.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunFreeze.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunManifest.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunPublish.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewRunSchema.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewScope.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewSkills.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ReviewStandards.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/RunUnitTests.Tests.ps1` | `2aa7ec` | `keep` | high-impact regression | Protects shared runner confinement, discovery, or execution from broad breakage. | — |
| Test | `tests/skalary/SelfImprovement.Tests.ps1` | `3a4498` | `transfer` | — | Self-improvement behavior transfers with SI ownership. | — |
| Test | `tests/skalary/Set-PlanStage.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/SetScriptApproval.Tests.ps1` | `623cc2` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/SiDue.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/SiHarvest.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/SiProposalCompletion.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/SiProposalSync.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/SiState.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/SiWriteScope.Tests.ps1` | `3a4498` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/Skalary.Tests.ps1` | `2aa7ec` | `keep` | high-impact regression | Protects shared runner confinement, discovery, or execution from broad breakage. | — |
| Test | `tests/skalary/SkillContracts.Tests.ps1` | `2aa7ec` | `keep` | external format | Protects a file contract consumed by Copilot customization tooling. | — |
| Test | `tests/skalary/SkillSize.Tests.ps1` | `2aa7ec` | `keep` | high-impact regression | Prevents recurring context-cost growth in always-loaded skills; prune to cap enforcement and hidden-mirror coverage. | — |
| Test | `tests/skalary/SuiteBudget.Tests.ps1` | `2aa7ec` | `delete` | — | Whole-suite budget machinery conflicts with focused local validation. | — |
| Test | `tests/skalary/SuiteCoverage.Tests.ps1` | `2aa7ec` | `delete` | — | Coverage-baseline machinery preserves the broad suite, not focused value. | — |
| Test | `tests/skalary/SuiteFixture.Tests.ps1` | `2aa7ec` | `keep` | high-impact regression | Protects shared runner confinement, discovery, or execution from broad breakage. | — |
| Test | `tests/skalary/SuiteOrdering.Tests.ps1` | `2aa7ec` | `keep` | high-impact regression | Protects shared runner confinement, discovery, or execution from broad breakage. | — |
| Test | `tests/skalary/SuiteProfile.Tests.ps1` | `2aa7ec` | `delete` | — | Whole-suite profiling machinery is removed rather than maintained. | — |
| Test | `tests/skalary/SuiteScriptHost.Tests.ps1` | `2aa7ec` | `keep` | high-impact regression | Protects shared runner confinement, discovery, or execution from broad breakage. | — |
| Test | `tests/skalary/SuiteTier.Tests.ps1` | `2aa7ec` | `delete` | — | Fast/Slow partition machinery is removed in favor of explicit scope. | — |
| Test | `tests/skalary/Test-Plan.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/ValidatePlan.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/VerticalLoop.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/WorkHierarchy.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Test | `tests/skalary/WorkHierarchyConsumerInstall.Tests.ps1` | `367e9a` | `transfer` | — | Subsystem test transfers with the behavior and formats its child owns. | — |
| Design note | `docs/design-notes/.design-notes.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/architecture/architecture-notes.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/architecture/autopilot-container-toolchain.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/autopilot-execution.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/autopilot-skill.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/fleet-dispatch.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/plan-workflow.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/plugin-evals.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/architecture/plugin-manager.design.md` | `623cc2` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/plugin-registry.design.md` | `623cc2` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/process-pr-comments.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/architecture/review-concern-authoring.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/review-reporting.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/self-improvement.design.md` | `3a4498` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/architecture/work-hierarchy-sync.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/explorations/agent-cost-optimization.design.md` | `2aa7ec` | `keep` | — | Operator-approved advisory cost budgets remain human-readable and add no enforcement service. | — |
| Design note | `docs/design-notes/explorations/asset-scanner-root-bound.design.md` | `623cc2` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/explorations/container-autopilot-watchdog.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/explorations/design-rfc-artifacts.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/explorations/explorations-and-experiments.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/explorations/intent-and-domain-capture.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/explorations/review-standards-tiering.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/explorations/review-system-enforcement-gaps.design.md` | `367e9a` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/explorations/si-cross-repo-proposal-protocol.design.md` | `3a4498` | `transfer` | — | Active subsystem guidance transfers to the child that owns the described behavior. | — |
| Design note | `docs/design-notes/project/ci-gates.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/project/copilot-customizations.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/project/design-note-writing-style.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Design note | `docs/design-notes/project/dev-rules.design.md` | `2aa7ec` | `keep` | — | Active baseline or unaffected-plugin guidance remains human-readable and is updated in place. | — |
| Architecture contract | `docs/architecture-notes/.architecture-notes.md` | `2aa7ec` | `keep` | — | Active human-readable architecture index remains the contract directory. | — |
| Architecture contract | `docs/architecture-notes/arch-eval-gate-separation.md` | `2aa7ec` | `keep` | — | Local structural-versus-LLM eval boundary remains readable guidance. | — |
| Architecture contract | `docs/architecture-notes/arch-install-confinement.md` | `623cc2` | `transfer` | — | Install confinement belongs with lifecycle and installer changes. | — |
| Architecture contract | `docs/architecture-notes/arch-review-run-v1.md` | `367e9a` | `transfer` | — | Review-run authority belongs with CR/DR and review evidence. | — |
| Architecture contract | `ARCH-Eval-Gate-Separation @ schemas/architecture/ARCH-Eval-Gate-Separation.json` | `2aa7ec` | `keep` | — | Preserve the logical eval-tier boundary while converting its source away from internal JSON. | — |
| Architecture contract | `ARCH-Install-Confinement @ schemas/architecture/ARCH-Install-Confinement.json` | `623cc2` | `transfer` | — | Logical installer boundary transfers with lifecycle ownership. | — |
| Architecture contract | `ARCH-Review-Run-V1 @ schemas/architecture/ARCH-Review-Run-V1.json` | `367e9a` | `transfer` | — | Logical review authority contract transfers with review ownership. | — |
| Architecture contract | `schemas/architecture/architecture-contract.schema.json` | `2aa7ec` | `delete` | — | Internal validation schema has no external consumer; Markdown contracts replace schema machinery. | — |

## Operator step 1.2: resolved tests

The operator retained both formerly uncertain tests with targeted pruning:

- `tests/skalary/ModelAllowlist.Tests.ps1` — keep the small core that prevents host-incompatible model bindings.
- `tests/skalary/SkillSize.Tests.ps1` — keep cap enforcement and hidden-mirror coverage to control recurring context cost.

No test is marked uncertain; each later child owns its transferred test disposition.

## Baseline closure

Step 3.3 closed all 78 rows owned by `2aa7ec`: 44 retained local or external-facing rows and 34
deletions. Retained paths are present, deleted paths are absent, hosted workflow files are absent,
and the two retained validation gates remain local. The other 216 rows already name exactly one
later child (`367e9a`, `3a4498`, or `623cc2`); they are transferred scope, not baseline residue.

This inventory remains plan-local evidence. It does not create a scanner, schema, policy service, or
recurring repository sweep.
