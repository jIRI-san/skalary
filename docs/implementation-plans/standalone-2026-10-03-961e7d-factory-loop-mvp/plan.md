# 961e7d: Factory loop MVP with loopback adapters
<!-- plan-id: 961e7d -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:637db77334791cd0811790f85b3891951118386dc0ac5009000581e43a91f2bc -->
<!-- execution-mode: manual -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Domain model - [assets/domain.md](assets/domain.md)
- Design - [assets/design.md](assets/design.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Review results - advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`
- AI-credit ledger - `assets/ai-credits.json` (created by autonomous execution)

## Phase 1: Installable plugin and real local playground

- [x] 1.1 Package factory-loop and guided project setup (REQ-1, REQ-2, RISK-1) `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** repository and global-style installed entry points discover an explicitly selected consumer and scaffold its non-secret configuration after approval.

  **Likely touchpoints:** `plugins/factory-loop/`, plugin manifests, config templates, setup skill, foreign-consumer tests, existing installer and marketplace generators.

  **Constraints:** use plugin-relative asset resolution and bound repository roots. Reuse explicit repository-local installation of planning/execution dependencies if their current paths require it; do not redesign all existing plugins. Installation remains confined to `.github`; declare other setup-owned consumer paths in `scaffolds[]`.

  **Verify:** `test:FactoryLoop.Install`, `test:FactoryLoop.Setup`, early non-repository asset and local dependency bootstrap assertions from `test:FactoryLoop.GlobalLayout`; generated registry, marketplace, bundle and dogfood drift checks.

  **Stop/escalate when:** global runtime support would require a cross-plugin path framework rather than an explicit local dependency bootstrap.

  </details>
- [ ] 1.2 Create loopback commands and disposable demo application (REQ-3, REQ-4, RISK-2) [after: 1.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** a local feature item, PR/checks, test/prod deployments, telemetry and bugs implement the live command contracts; acceptance executes against real immutable demo artifacts.

  **Likely touchpoints:** factory-loop adapter examples, demo templates and controls, `tests/factory-loop/`.

  **Constraints:** no external credentials/network calls. Label infrastructure simulated. Demo merge control performs an actual Git merge; record PR source SHA, merge commit and immutable snapshot digest separately. Promote that same snapshot despite later HEAD edits; status flags cannot create acceptance success. Demo mutation stays in the explicitly created disposable project.

  **Verify:** `test:FactoryLoop.AdapterContract`, `test:FactoryLoop.DemoArtifact`.

  **Stop/escalate when:** the fixture needs a server/service dependency; prefer a small PowerShell application and CLI acceptance first.

  </details>

## Phase 2: Issue-to-PR chain and recoverable polling

- [ ] 2.1 Implement finite ticks, checkpoints and provider reconciliation (REQ-5, REQ-6, REQ-7, RISK-3) [after: 1.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** one chain per project can wait for checks and human PR merge, resume after restart, and reconcile a side effect that completed before checkpoint persistence.

  **Likely touchpoints:** factory-loop PowerShell runner, local checkpoint/lock, command result validation, deterministic state fixtures.

  **Constraints:** no service, database or general scheduler. Polling is zero-AI; default interval 60 seconds. Persist/derive operation keys before side effects and assert reconciled provider identity. Closed unmerged PR, cancelled/failed checks, changed head and superseded deployment are explicit outcomes. Do not change existing agent elapsed-time rules.

  **Verify:** `test:FactoryLoop.Tick`, shared protocol and PR cases in `test:FactoryLoop.Restart`, `test:FactoryLoop.PrChecks`; later mutation proofs belong to steps 3.2 and 4.1.

  **Stop/escalate when:** an adapter cannot identify/reconcile a mutation; pause unknown outcome instead of retrying blindly.

  </details>
- [ ] 2.2 Connect initial plan confirmation, implementation and build repair (REQ-8, REQ-9, REQ-10, RISK-4) [after: 2.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** an idea routes to /cip, a linked plan is validated, and confirmed work routes to /ci; actual implementation commits and a PR progress through build repair to human merge.

  **Likely touchpoints:** factory setup/run skills, existing autopilot launcher/agent factory-repair mode, CIP/CI admission scripts, factory-owned acceptance authoring asset, usage ledger integration.

  **Constraints:** initial work uses ordinary /ci admission. A narrowly opt-in repair mode on the existing launcher validates the original plan with Test-PlanCriteriaBaseline, skips completed-phase admission and forbids criteria/marker writes; no second CLI wrapper. Factory-owned deployed acceptance context is optional for /cip. At most two repair PRs per incident and two corrective invocations per stable build-incident lineage across successor PRs/heads. Aggregate planning, implementation and repair usage idempotently by execution identity.

  **Verify:** `test:FactoryLoop.PlanAdmission`, `test:FactoryLoop.AgentHandoff`, `test:FactoryLoop.RepairBounds`, `test:FactoryLoop.Credits`.

  **Stop/escalate when:** an action would weaken acceptance, exceed permission/allowance or widen confirmed scope.

  </details>

## Phase 3: Deployed acceptance and production gate

- [ ] 3.1 Validate the test artifact and observe its telemetry window (REQ-11, REQ-12, REQ-13, RISK-5) [after: 2.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** pipeline success, expected immutable artifact and observed running version agree before feature acceptance and bounded telemetry observation can pass.

  **Likely touchpoints:** environment profiles, deployment/version/check/telemetry commands, current result normalization.

  **Constraints:** default demo observation is five minutes; deterministic tests inject a clock rather than sleep. Unknown access is blocked/inconclusive. Pre-prod uses the same profile shape; the demo actively exercises test and prod.

  **Verify:** `test:FactoryLoop.DeploymentIdentity`, `test:FactoryLoop.Acceptance`, `test:FactoryLoop.Telemetry`.

  **Stop/escalate when:** environment identity, query coverage or production-safe checks cannot be established.

  </details>
- [ ] 3.2 Gate production promotion and complete bounded repair cycles (REQ-14, REQ-15, REQ-16, RISK-6) [after: 3.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** explicit artifact-specific approval permits production triggering; failed validation creates/deduplicates a bug and follows a fix PR through the same test/prod chain.

  **Likely touchpoints:** human decision resume controls, bug adapter, incident counters, promotion dispatch, production acceptance.

  **Constraints:** unanswered approval waits with zero AI; decline blocks promotion. Native pipeline approvals still apply. A repaired artifact needs a new promotion decision. No automatic PR merge or rollback. Resolve a bug only after the original failing check passes on its repair deployment.

  **Verify:** `test:FactoryLoop.ProductionApproval`, `test:FactoryLoop.BugCycle`, `test:FactoryLoop.InaccessibleProduction`, bug/promotion crash cases in `test:FactoryLoop.Restart`.

  **Stop/escalate when:** repeated failure exhausts the incident budget or the failure is not reproducibly attributable to in-scope application behavior.

  </details>

## Phase 4: Evidence, installed dry runs and evaluation

- [ ] 4.1 Publish sanitized evidence and complete work items (REQ-17, REQ-18, RISK-7) [after: 3.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** version-bound evidence commits land on a separate branch/worktree before final issue closure; interruption can resume without duplicate records or closures.

  **Likely touchpoints:** evidence writer, Git helpers, secret screening, work-item close operation.

  **Constraints:** no raw logs/customer data. Evidence branch is never merged into main. Reference validated source rather than routinely merging main. Setup verifies exclusion from deployment triggers or blocks evidence publication readiness.

  **Verify:** `test:FactoryLoop.Evidence`, `test:FactoryLoop.Completion`, evidence/closure crash cases in `test:FactoryLoop.Restart`.

  **Stop/escalate when:** evidence cannot be safely published or the target pipeline exclusion cannot be verified with the project owner.

  </details>
- [ ] 4.2 Prove deterministic end-to-end and installed-consumer behavior (REQ-19, REQ-20, RISK-8) [after: 4.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** zero-credit replay drives the installed loop through real local artifact checks, Git evidence and fault recovery; both supported installation layouts have closure tests.

  **Likely touchpoints:** `tests/factory-loop/`, consumer fixtures, plugin structural evals, replay commands.

  **Constraints:** injected clock, deterministic implementation stand-in and simulated providers are labeled; no LLM in build/test. Split focused cases to respect local command deadlines rather than add an aggregate gate.

  **Verify:** `test:FactoryLoop.EndToEnd`, `test:FactoryLoop.FaultMatrix`, `test:FactoryLoop.GlobalLayout`; plugin-focused structural eval.

  </details>
- [ ] 4.3 Add opt-in agent evals and operator documentation (REQ-21, REQ-22, RISK-8) [after: 4.2] `S`
  <details><summary>Implementation contract</summary>

  **Outcome:** agent-driven demo and small Waza cases check observable planning/repair behavior; documentation explains scheduler setup, controls, adapters and limits.

  **Likely touchpoints:** factory-loop Waza specs/fixtures, offline grader-shape tests, operator guide, new factory-loop design note and root index, related planning/eval/plugin notes.

  **Constraints:** write-enabled evals require disposable isolation; premium routes remain explicit. No hosted Skalary workflow, live credentials or live provider success requirement. Update source and generated distribution via existing generators.

  **Verify:** `test:FactoryLoop.EvalContract`, `test:FactoryLoop.Documentation`, `review:cr`; explicit premium smoke only at operator request.

  </details>
