# Drafting Guide (`cip` Step 4)

> Read this asset when drafting or refining `plan.md`. Keep the plan compact, executable, and machine-verifiable.

## Step drafting checklist

1. Use `./assets/plan-template.md` structure.
2. Keep steps as checklist lines, not prose blocks.
3. Every step references at least one `REQ-N`.
4. Add `[after: X.Y]` where dependencies exist.
5. Assign `S`, `M`, or `L` for each step.
6. Use `@human` only for true human-only actions.

## Evidence legend (required in Acceptance Criteria guidance)

Typed evidence markers:
- `test:<TestId>`
- `file:<path>#exists`
- `file:<path>#contains:<regex>`
- `file:<path>#count>=<N>`
- `file:<path>#dircount>=<N>`
- `review:cr|dr`

Every `REQ-N` must have at least one acceptance criterion containing at least one typed marker.

## Concision and decisions extraction

- Multi-paragraph rationale belongs in `decisions/<topic>.md`.
- Keep `plan.md` focused on requirements, risks, and executable steps.
- Link to extracted decisions from the Decisions section with one-line summaries.

## Size limits

- Warn at **20KB** or **400 lines**.
- Block at **35KB** or **700 lines**.

When approaching limits:
1. Extract rationale into `decisions/`.
2. Tighten step wording to action + scope + IDs.
3. Split oversized concerns into a sibling plan if needed.

## Phase budget guidance

- Include `<!-- phase-budget-points: N -->` in the plan header.
- Use `S=1`, `M=2`, `L=3` point mapping.
- Treat cap 6 per phase as advisory unless explicitly overridden in Decisions.

## State anchor and validator cadence

- Set/update the stage anchor with `Set-PlanStage.ps1 -Stage drafted` after drafting (never hand-edit `<!-- cip-stage: ... -->`).
- Re-run `Test-Plan.ps1 -Stage Draft` after drafting and after each DR round.

## Capture (`capture.md`)

Durable interview/assumption notes are written **script-only** via `Add-WorkflowNote.ps1 -Kind Capture` into the plan-folder `capture.md` (it owns the `## Capture` header, the `No entries for this phase.` placeholder, placeholder-replace, and free-text sanitization):

```powershell
# initialize the phase section (no -Message)
pwsh -NoProfile -File scripts/skalary/Add-WorkflowNote.ps1 -Kind Capture -PlanDir <plan-folder> -Phase <N>
# record an interview decision/assumption
pwsh -NoProfile -File scripts/skalary/Add-WorkflowNote.ps1 -Kind Capture -PlanDir <plan-folder> -Phase <N> -Step <source-step> -Src note -Message "interview: <decision or assumption>"
```

Initialize the section and commit `capture.md` by explicit filename at phase start even if empty; commit again when entries are appended. Missing required sections/placeholders fail loud; an intentionally empty `No entries for this phase.` stays valid.

## `ledger-consult` (on-demand, before drafting)

When a plan folder includes `docs/review-ledger/`, consult only the small category files relevant to the current change; never auto-load the full ledger.

Rules:
- Exclude `docs/review-ledger/.archive/` from all reads.
- Prefer targeted reads by category, then optional `#tag` filtering inside the selected file(s).
- Keep reads narrow (only categories implied by requirements/risks under discussion).

7-category mapping rubric (keyword / REQ-class -> file):

| Signal in request/REQ/RISK | Ledger file |
|---|---|
| auth, trust boundary, injection, secrets, ACL, threat model, OWASP | `docs/review-ledger/security.md` |
| latency, throughput, N+1, allocation pressure, scaling | `docs/review-ledger/performance.md` |
| exception flow, retries, timeouts, fail-loud behavior | `docs/review-ledger/error-handling.md` |
| naming drift, duplicated logic, contract mismatch, parity issues | `docs/review-ledger/consistency.md` |
| phase ordering, dependency gates, acceptance evidence, crosscheck flow | `docs/review-ledger/plan-structure.md` |
| unit/integration evidence, flaky tests, fixture quality, coverage gaps | `docs/review-ledger/testing.md` |
| logs, metrics, tracing, diagnosability, receipt/audit visibility | `docs/review-ledger/observability.md` |
