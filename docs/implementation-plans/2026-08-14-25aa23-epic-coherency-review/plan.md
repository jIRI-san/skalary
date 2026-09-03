# 25aa23: Epic coherency review
<!-- plan-id: 25aa23 -->
<!-- depends-on: 8a0644 -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle. -->

<!-- execution-mode: manual -->
<!-- scope: step -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Evolution log - [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt - `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)

## Phase 1: Fixed coherency review
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Define one fixed epic-coherency scope over goal and done coverage, verticality, child independence and overlap, shared ownership, necessary acyclic dependencies, MVP-to-final route, and prior-art reuse; invoke existing design-review agents through review-run v1 (REQ-1, REQ-5, RISK-1, RISK-4) `M`
- [x] 1.2 Add the proportionality rubric that compares every proposed mechanism to confirmed operator intent, classifies it as local fix, required shared contract, or speculative platform, detects cross-child duplication, requires one owner, and challenges infrastructure-only dependency edges (REQ-2, REQ-3, RISK-2, RISK-3) [after: 1.1] `M`

## Phase 2: Resolve and finalize the cut
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Extend confined `New-Epic.ps1` to atomically replace one bounded provisional verdict and finding-resolution block before review, binding exact verified finding task-id/title pairs to one proportionality class, blocking state, operator decision, and concrete keep, simplify, split, or defer action; reject stale source, malformed markers, links, duplicates, conflicts, and non-allowlisted writes, while review-run v1 remains authority (REQ-1, REQ-4, RISK-1, RISK-5) [after: 1.2] `M`
- [x] 2.2 Integrate the fixed review into `/cep` after operator acceptance: materialize the complete epic-only source before child scaffolding, invoke installed `/dr`, require Freeze/Publish/verified readers plus complete attendance, return decision-changing findings to the interactive operator, update the bounded block through `New-Epic.ps1`, and reconfirm/review every source change until a finding-free current-byte run permits finalization without another write; synchronize the installed payload in this step (REQ-2, REQ-3, REQ-4, RISK-2, RISK-3, RISK-4, RISK-5) [after: 2.1] `M`
- [x] 2.3 After deterministic `/ci` admission and before each epic child run, apply the same prompt-level rubric to the current plan plus existing epic rollup/verdict metadata without reading sibling bodies; compare against the verified epic digest and Git history, record compact keep/simplify/split/defer prose in the existing epic verdict or current-plan decisions, and block interactive or headless execution only on unresolved overcomplication without adding review state (REQ-2, REQ-3, REQ-4, REQ-7, RISK-2, RISK-3, RISK-5, RISK-6) [after: 2.2] `S`

## Phase 3: Distribution and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Add focused fixtures for minor-finding escalation, duplicated mechanisms, owner conflicts, unnecessary dependencies, demonstrated cross-plan invariants, pre-run stale-plan detection, and compact verdict persistence; synchronize existing plugin/generated copies (REQ-3, REQ-5, REQ-6, REQ-7, RISK-2, RISK-4, RISK-5, RISK-6) [after: 2.3] `M`
- [ ] 3.2 Run focused coherency, installed-consumer, review-run, and generated-drift checks; rebuild the existing evidence receipt and complete final intent/requirement review (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6) [after: 3.1] `M`
