# 3a4498: Simple self-improvement
<!-- plan-id: 3a4498 -->
<!-- depends-on: 367e9a, 33a78a -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:e3f0dd49fac64f307d8d5a8220f34c36bbf98f5a205153c5d921f24a74496b65 -->
<!-- epic: 705e6c -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Domain model — [assets/domain.md](assets/domain.md)
- Approved design — [assets/design.md](assets/design.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Review results — advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`
- AI-credit ledger — `assets/ai-credits.json` (created by autonomous execution)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Direct bounded self-improvement
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit).
     Nontrivial AI steps carry a compact details block with Outcome, Likely touchpoints, Constraints,
     Verify, and—when uncertain or high risk—Stop/escalate when. Omit it for self-explanatory S work. -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Decouple the strict recent-learning reader from SI receipts and lifecycle state while preserving its bounded committed-input validation and four observable outcomes (REQ-1, REQ-6, RISK-1, RISK-4) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** `Get-SiHarvest.ps1` is a read-only adapter over the single committed recent-learning handoff and has no receipt, due, run, candidate, CAS, or state-store dependency.

  **Likely touchpoints:** `plugins/self-improvement/scripts/Get-SiHarvest.ps1`, its manifest mapping, generated closure, and `tests/skalary/RecentLearning.Tests.ps1`.

  **Constraints:** retain the 16 KiB and 10-item limits, strict Markdown metadata, completed source-plan and ancestry checks, citation checks, secret refusal, collision-safe fence, and distinct `missing`, `empty`, `valid`, and `stale` results.

  **Verify:** focused reader tests prove all four outcomes and every retained malformed/oversized/secret/citation refusal without creating state.

  **Stop/escalate when:** preserving a reader check appears to require reintroducing durable state; stop and resolve the check directly from Git and the handoff instead.

  </details>
- [ ] 1.2 Replace `/si` proposal lifecycle with one local select-and-edit interaction guarded by canonical Markdown path checks before and after mutation (REQ-2, REQ-3, REQ-8, RISK-1, RISK-2, RISK-3, RISK-6) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** one `/si` run reads the retained handoff, verifies repository evidence, ranks at most five cited proposals, applies only individually selected proposals in the current worktree, runs required trusted synchronization, and shows the resulting diff and focused validation.

  **Likely touchpoints:** `plugins/self-improvement/skills/si/**`, `scripts/skalary/Test-SiWriteScope.ps1`, bundled/dogfood guard copies, and focused SI/write-scope tests.

  **Constraints:** direct targets are limited to `.github/copilot-instructions.md`, canonical plugin skill/agent/prompt Markdown, design notes, and architecture notes. Generated `.github` copies, workflows/actions, executable code, plans/runtime state, and all other paths are refused. Existing unrelated edits are preserved; a selected target already modified outside the run stops for operator action. Trusted sync output is allowed only after a selected canonical plugin Markdown edit.

  **Verify:** focused tests cover individual selection, no-selection/no-write, informed VS Code/CLI choices, dirty-target refusal, canonical allowed paths, generated/executable/workflow refusal, physical link escape, trusted sync ordering, visible diff, and validation failure.

  **Stop/escalate when:** a candidate requires an out-of-scope or executable target, architecture maturity promotion, or an edit that cannot be separated from existing local changes; route plan-sized work to `/cip` or stop for the operator.

  </details>
- [ ] 1.3 Replace broad lifecycle assertions with the smallest deterministic `/si` reader, selection, write-scope, and failure-path test set (REQ-1, REQ-2, REQ-3, REQ-8, RISK-1, RISK-2, RISK-6, RISK-7) [after: 1.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** deterministic tests protect each retained user-visible state and safety boundary without testing removed proposal identities, receipts, stores, branches, or provider synchronization.

  **Likely touchpoints:** `tests/skalary/{RecentLearning,SelfImprovement,SiWriteScope}.Tests.ps1` and `plugins/self-improvement/evals/self-improvement.Tests.ps1`.

  **Constraints:** keep behavior-oriented cases only; reuse existing reader fixtures and test helpers before adding new ones.

  **Verify:** the selected tests run through the focused repository command and every retained test maps to REQ-1, REQ-2, REQ-3, or REQ-8.

  </details>

## Phase 2: Stateless feedback and lifecycle retirement
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Make `/pfb` a stateless interactive delivered-vs-intent comparison with an optional direct `/cip` handoff, and remove headless queue/enqueue behavior from `/ci` and autopilot (REQ-4, REQ-6, RISK-5) [after: 1.3] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** interactive `/pfb` presents an evidence-cited alignment reading, records no queue or verdict state, and starts a correction plan only when the operator selects that action; headless completion skips feedback without inventing or persisting a verdict.

  **Likely touchpoints:** `plugins/self-improvement/skills/pfb/**`, `plugins/continue-implementation/skills/ci/SKILL.md`, `plugins/autopilot/agents/autopilot.agent.md`, and focused PFB/integration tests.

  **Constraints:** retain the five-section intent comparison, closed `full|partial|missed` verdict, cited evidence, and operator-authored correction; do not write a queue, invoke SI, or block plan completion.

  **Verify:** focused tests prove interactive comparison and correction-plan handoff, plus the absence of queue writes and headless feedback calls.

  </details>
- [ ] 2.2 Delete the obsolete SI/PFB due, queue, lifecycle, receipt, CAS, repair, archive, cross-repository, worktree, branch, PR, schema, scaffold, and state surfaces; close manifest and source references atomically (REQ-5, REQ-6, REQ-7, RISK-3, RISK-4, RISK-5) [after: 2.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** the self-improvement plugin contains only the two direct skills, their necessary Markdown assets, the bounded reader and guard closures, and focused evals; no obsolete runtime state or caller remains.

  **Likely touchpoints:** `plugins/self-improvement/{plugin.json,scripts,schemas,skills,prompts,evals}`, `.github/skills/{si,pfb}`, `.github/prompts`, `docs/{feedback,self-improvement}`, autopilot integration scripts, registry/marketplace surfaces, and transferred SI test files.

  **Constraints:** keep `docs/feedback/recent-learning.md`, the read-only reader dependencies, and the physical write guard. Delete `docs/feedback/queue.md`, `docs/self-improvement/**`, cross-repo transport, proposal publication, and their tests rather than retaining compatibility adapters.

  **Verify:** a closed residue assertion finds no active reference to removed commands, files, schemas, state paths, queue behavior, or PR lifecycle, while plugin install still supplies the retained SI/PFB surfaces.

  **Stop/escalate when:** an allegedly removable format is proven to have an external consumer outside this repository; stop for an explicit compatibility decision rather than adding an adapter.

  </details>
- [ ] 2.3 Replace retired lifecycle suites with focused stateless PFB, plugin-manifest, caller, residue, and installed-consumer tests (REQ-4, REQ-5, REQ-6, REQ-7, RISK-3, RISK-4, RISK-5, RISK-7) [after: 2.2] `S`

## Phase 3: Guidance, distribution, and closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Reconcile self-improvement and operator guidance with the direct local flow, retire the superseded cross-repo exploration, and document visible failure/no-rollback behavior (REQ-4, REQ-5, REQ-7, REQ-8, RISK-3, RISK-4, RISK-6) [after: 2.3] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** active design notes, indexes, operator guides, prompts, and repository descriptions describe only the retained stateless PFB and direct SI behavior.

  **Likely touchpoints:** `docs/design-notes/{.design-notes.md,architecture/self-improvement.design.md,explorations/si-cross-repo-proposal-protocol.design.md}`, `docs/operator-guide/**`, `README.md`, and self-improvement prompts.

  **Constraints:** preserve the current direct-workflow input contract and the accepted single-operator boundary; delete superseded guidance rather than documenting retired compatibility.

  **Verify:** active-document residue checks find no queue, due, receipt, repair, cross-repo, PR, or lifecycle instructions and all remaining links resolve.

  </details>
- [ ] 3.2 Run existing script sync, registry/marketplace generation, dogfood sync, and focused self-improvement/consumer validation so canonical sources and installed copies converge (REQ-3, REQ-5, REQ-7, REQ-8, RISK-2, RISK-3, RISK-4, RISK-7) [after: 3.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** manifests, generated closures, catalogs, dogfood copies, and consumer installation expose exactly the retained SI/PFB surface with no stale payload.

  **Likely touchpoints:** existing `Sync-PluginScripts`, `Build-Registry`, `Build-Marketplace`, `Sync-Dogfood`, focused validator, and consumer-install commands plus their generated outputs.

  **Constraints:** use existing generators in repository-defined order; do not hand-edit generated copies or introduce a new synchronization wrapper.

  **Verify:** detect-only drift checks, self-improvement focused tests, and installed-consumer assertions pass with zero retired files.

  </details>
- [ ] 3.3 Run direct evidence and one risk-selected whole-plan CR over the completed direct flow and deletion closure (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7) [after: 3.2] `S`
