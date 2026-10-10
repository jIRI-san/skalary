# 1a4feb: Docker app CI live acceptance
<!-- plan-id: 1a4feb -->
<!-- cip-stage: scaffolded -->
<!-- planning-confirmed: pending -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: none -->

## Assets

- Intent - [assets/intent.md](assets/intent.md)
- Domain - [assets/domain.md](assets/domain.md)
- Design and live operator protocol - [assets/design.md](assets/design.md)
- Requirements - [assets/requirements.md](assets/requirements.md)
- Risks - [assets/risks.md](assets/risks.md)
- Decisions - [assets/decisions.md](assets/decisions.md)
- References - [assets/references.md](assets/references.md)
- Bounded execution decisions - [assets/unattended-decissions.md](assets/unattended-decissions.md)
- Exact isolated usage - `assets/ai-credits.json`, created only from real CLI sidecars

## Phase 1: Human-safe readiness

- [ ] 1.1 Authorize dependent fixture work (REQ-1, RISK-1) @human `S`
  <details><summary>Human authorization</summary>

  **Steps:**
  1. Inspect accepted independent work and the no-approval resume with the parent/operator.
  2. Obtain a separate explicit operator authorization for dependent work.
  3. Record only this human mark and its authorization in the coordinator; commit between worker visits.

  **Verify:** the authorization names plan 1a4feb and step 1.1. Planning, transport, and runtime permissions do not satisfy it.

  **Rollback:** before a dependent worker starts, withdraw authorization through the parent and make a new commit restoring this unchecked state. Preserve prior commits; no reset or deletion.

  </details>
- [ ] 1.2 Write independent.txt with `independent` and an LF newline (REQ-2, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-7) `S`
  <details><summary>Implementation contract</summary>

  **Outcome:** `smoke/app-ci/1a4feb/independent.txt` is exactly 12 ASCII bytes: `independent` followed by one LF.

  **Likely touchpoints:** this file, this checklist, and `assets/unattended-decissions.md`.

  **Constraints:** no dependent/second file, human completion, criteria edits, worker PR, recursive coordination, or changes outside the authorized fixture/progress boundaries. Record the byte-writing method, criterion, rationale, and consequence.

  **Verify:** current `file:` marker and `test:docker-independent-bytes` from the focused assertion in the design. Commit source, checkbox, and bounded decision atomically.

  **Stop/escalate when:** the named Docker target, full HEAD, settings, permission, or confirmed baseline cannot be established. Return committed partial work and human blocker, not phase closure.

  </details>
- [ ] 1.3 Write dependent.txt with `dependent` and an LF newline (REQ-3, RISK-1, RISK-2) [after: 1.1, 1.2] `S`
  <details><summary>Implementation contract</summary>

  **Outcome:** `smoke/app-ci/1a4feb/dependent.txt` is exactly 10 ASCII bytes: `dependent` followed by one LF.

  **Likely touchpoints:** this file and this checklist.

  **Constraints:** both prerequisites are committed and authorized; preserve independent.txt bytes and source blob. This fresh Phase 1 visit never starts Phase 2 or finalizes.

  **Verify:** current `file:` marker, `test:docker-dependent-bytes`, and unchanged independent blob. Commit source and checkbox atomically.

  **Stop/escalate when:** human authorization, completed prerequisite admission, current HEAD, or exact evidence fails. Preserve work and report to parent.

  </details>

## Phase 2: Accepted-head continuation

- [ ] 2.1 Write second.txt with `second` and an LF newline (REQ-4, RISK-2, RISK-6) [after: 1.3] `S`
  <details><summary>Implementation contract</summary>

  **Outcome:** `smoke/app-ci/1a4feb/second.txt` is exactly 7 ASCII bytes: `second` followed by one LF.

  **Likely touchpoints:** this file and this checklist.

  **Constraints:** Phase 1 is closed; start at its accepted full HEAD; preserve both earlier blobs. This phase worker never archives or publishes a PR.

  **Verify:** current `file:` marker, `test:docker-second-bytes`, and all three exact byte assertions. Commit source and checkbox atomically.

  **Stop/escalate when:** earlier closure, expected HEAD/ancestry, or current evidence fails. Finalization is a separate fresh target after local acceptance.

  </details>
