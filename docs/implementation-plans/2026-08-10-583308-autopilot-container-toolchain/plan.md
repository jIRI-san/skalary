# 583308: Autopilot container toolchain
<!-- plan-id: 583308 -->
<!-- epic: 33b1f9 -->
<!-- cip-stage: dr-round-3 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 9 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: none -->

## Assets

`plan.md` contains the workflow markers, asset index, and executable steps; supporting rationale and records live under `assets/`.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Design-review evolution — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Local image evidence — `assets/measurements/container-toolchain-receipt.json`, `assets/measurements/container-toolchain-provenance.json`
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Baseline and image contract
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add plugin-owned line-oriented `plugins/autopilot/devcontainer/toolchain.tsv` as the sole additional-tool baseline owner (`case-id`, Debian package, conventional command), with stable unique case IDs for every row in `assets/decisions/container-toolchain-contract.md`; the existing bootstrap package literal remains a separately named set excluded from equality. Update the first Debian apt layer, before Microsoft or Docker repositories, to reject active apt source hosts outside `deb.debian.org` and `security.debian.org`, install bootstrap plus manifest packages with `--no-install-recommends`, capture OS/source/package/dependency provenance before apt cleanup, and retain floating versions under the existing policy. Map the manifest, patch-bump autopilot, synchronize dogfood/marketplace/registry, and pass drift checks in this step (REQ-1, REQ-3, REQ-5, RISK-1, RISK-2, RISK-5, RISK-7) `L`
- [x] 1.2 Add plugin-owned `plugins/autopilot/devcontainer/container-toolchain-smoke.sh`; copy the manifest and smoke into root-owned `/usr/local/share/autopilot` and `/usr/local/bin` before the literal `USER autopilot` anchor; create exact root-owned `fd` and `bat` links; and emit at most 64 KiB of single-line JSON matching a closed schema with only case IDs, pass/fail state, bounded version/origin fields, and digests. Map both files in `plugin.json`, patch-bump autopilot, run dogfood/marketplace/registry generation, and pass their drift checks in the same step (REQ-1, REQ-2, REQ-3, REQ-5, RISK-2, RISK-3, RISK-4, RISK-5) [after: 1.1] `L`
- [x] 1.3 Update the autopilot execution design note with baseline categories, exclusions, floating policy, Linux-only scope, extension anchor, and advisory size threshold; correct its stale Dockerfile path. Add `test:AutopilotContainer.ToolchainContract` to prove three-way equality among manifest case/package sets, Dockerfile installation source, and smoke `CASE:` IDs; mutate one package and one smoke case to prove failure. Also verify Debian-layer/origin enforcement, exact alias targets/ownership/non-writable parent, root-before-user placement, JSON bounds/schema, manifest/dogfood hashes, and launcher context without Docker (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5) [after: 1.2] `L`

## Phase 2: Always-reported conditional image gate
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add repository-owned `scripts/skalary/Invoke-ContainerToolchainGate.ps1` as the sole local/CI runner and path-set owner. It accepts validated 40-hex base/candidate SHAs and explicit checkout roots, supports `Detect`, `Measure`, and `VerifyResult`, uses NUL-delimited Git paths with ordinal literal matching, derives canonical/installed paths from `plugin.json` plus Dockerfile `COPY` sources, treats every unusable detection base as `relevant=true`, and writes a bounded terminal `skalary/container-toolchain-receipt@1` JSON receipt from `finally` for success, irrelevant, build failure, smoke failure, invalid output, internal timeout, and unexpected error. Add `test:AutopilotContainer.GateRunnerContract` for PR-merge/push identity, unusable-base relevance, hostile paths, payload parity, candidate-only reasons, full detector/image truth table, JSON/Markdown encoding, advisory inputs, process timeout/kill, fallback receipt, and determinism (REQ-3, REQ-4, REQ-5, RISK-1, RISK-4, RISK-6, RISK-7) [after: 1.3] `L`
- [x] 2.2 Atomically add the complete operational `.github/workflows/autopilot-container-ci.yml` and no earlier partial workflow. Register it as a third host in `docs/design-notes/project/ci-gates.design.md`; extend `tests/CiWorkflow.psm1`; create exact producer `test:Ci.WorkflowSecurityContract`; and extend existing `test:CiGates.InventoryMatchesWorkflow` with universal versus registry/image-specific job rules. Use unfiltered PR/main triggers, final check `autopilot container / gate`, read-only permissions, full-SHA actions, credential-free checkout, concurrency, 5-minute detector/final and 45-minute image timeouts. For PRs, execute the control-plane runner from a credential-free checkout pinned to validated base SHA; for trusted `main` pushes, use candidate `main`. Candidate code gets no secrets, command files, socket/workspace mount, privilege, device, capability, or host network. Bind PR candidate/base to `github.sha`/`pull_request.base.sha`, push candidate/base to `github.sha`/`github.event.before`, assert checkout HEADs, and use one pair for detection/build; unusable detection base forces relevance and candidate-only measurement. Build/smoke candidate first with a 25-minute budget; then use at most 10 residual minutes for comparable base, classifying base build failure/timeout as candidate-only. Use one pulled base image, `linux/amd64`, daemon, explicit Copilot version, and local BuildKit cache. Validate bounded smoke JSON, always upload terminal receipt/provenance for 14 days under `if: always()`, and render only encoded fields/digest. Detector non-success fails; only irrelevant/skipped or relevant/success passes; over 250 MiB stays advisory (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-3, RISK-4, RISK-6, RISK-7) [after: 2.1] `L`

## Phase 3: Distribution reconciliation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Run the ordinary suite and structural evals, then invoke `Invoke-ContainerToolchainGate.ps1 -Mode Measure` locally against the synchronized installed candidate and an explicit base. Record candidate/base elapsed times and receipt digest; require candidate build/smoke within 25 minutes, optional base work within 10 residual minutes, runner within 35 minutes, and workflow job within 45 minutes. Prove path closure, third-host gate inventory, payload parity, failure receipts, and generated outputs are clean; if measured growth exceeds 250 MiB, add `assets/decisions/image-size-exception.md` with package attribution and operator rationale before finalization (REQ-3, REQ-4, REQ-5, RISK-1, RISK-3, RISK-4, RISK-6, RISK-7) [after: 2.2] `M`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 4.1 Review the package baseline, acquisition trust, advisory image-size measurement, non-root smoke evidence, receipt/provenance artifact, and payload synchronization before approving the plan (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, RISK-1, RISK-2, RISK-4, RISK-5, RISK-6, RISK-7) @human [after: 3.1] `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Review the measured before/after image sizes and the exact installed package list.
  2. Run `@cr` on the manifest, Dockerfile, smoke script, shared runner, workflow, tests, design note, receipt, and generated payload changes.
  3. Approve only when the built image passes every functional check as `autopilot`, the receipt proves an allowed Debian origin and bounded execution, no secret/socket/privilege channel was added, and any growth above the advisory threshold has `assets/decisions/image-size-exception.md`.

  **Verify:** `review:cr` is recorded; ordinary `test:AutopilotContainer.ToolchainContract`, `test:AutopilotContainer.GateRunnerContract`, `test:Ci.WorkflowSecurityContract`, and `test:CiGates.InventoryMatchesWorkflow` pass; the local receipt and relevant workflow run show candidate smoke success; and plugin/dogfood/marketplace/registry drift checks pass.

  **Rollback:** before merge, return the affected step to `[~]`, remove or replace the disputed package, synchronize the payload, and repeat the runner. After merge, use a privileged revert/follow-up plugin version and regenerated outputs. If external branch protection later requires `autopilot container / gate` and an outage blocks repair, an administrator temporarily removes only that required-check name, records the incident, merges the reviewed repair, restores the check, and verifies one irrelevant no-op and one relevant image run; this plan does not itself change branch protection.

  </details>
