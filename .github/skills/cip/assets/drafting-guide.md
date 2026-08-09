# Drafting Guide (`cip` Step 3)

> Read this asset when drafting or refining `plan.md`. Keep the plan compact, executable, and machine-verifiable.

## Step drafting checklist

1. Use `./assets/plan-template.md` structure.
2. Keep steps as checklist lines, not prose blocks.
3. Every step references at least one `REQ-N`.
4. Add `[after: X.Y]` where dependencies exist.
5. Assign `S`, `M`, or `L` for each step.
6. Use `@human` only for true human-only actions, and give each one the detail block below.

## `@human` step detail (blocking)

Every `@human` step is an operator round-trip: under autopilot the run stops (`exit 42`) and a person has to
act. `Test-Plan.ps1` enforces the `human-step-detail` gate — an `@human` step whose `<details>` block is
missing **Steps**, **Verify**, or **Rollback** fails the plan. Write all three so the round-trip is
single-pass instead of a question-and-answer loop:

```markdown
- [ ] 4.2 Operator gate (REQ-7) @human `S`
  <details><summary>Details</summary>

  **Steps:**
  1. What the operator does, in order, with exact commands or portal paths.

  **Verify:** the concrete observable condition that proves it worked.

  **Rollback:** how to undo it (or state plainly that there is no clean undo).

  </details>
```

- The three labels may be bold headings or bold-prefixed list items; the gate accepts both.
- Fenced commands inside the block are preserved verbatim — put the real command there, not a description of it.
- `Get-PlanState` prints this block under `Handoff:` when the next step is `@human`, so what you write here is exactly what the operator reads.
- Archived plans are exempt (warn-only): the gate governs plans being drafted and executed, not historical records.
- Concentrate `@human` steps at phase ends so a plan collects its operator round-trips instead of scattering them.

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

- Multi-paragraph rationale belongs in `assets/decisions/<topic>.md`.
- Keep `plan.md` to the header markers, the asset index, and the executable steps; requirements, risks, and decisions live in `assets/`.
- Link to extracted decision records from `assets/decisions.md` with one-line summaries.

## Size limits (`plan.md` only)

Both thresholds are **warnings** in `Test-Plan.ps1` — neither blocks. Treat them as drafting discipline, not a gate:

- Warn at **20KB** or **400 lines**.
- Second, louder warning at **35KB** or **700 lines** (advisory in the validator).

When approaching limits:
1. Extract rationale into `assets/decisions/`.
2. Tighten step wording to action + scope + IDs.
3. Split oversized concerns into a sibling plan if needed.

## Phase budget guidance

- Include `<!-- phase-budget-points: N -->` in the plan header. `Test-Plan.ps1` reads this marker and warns per phase against it; when the marker is absent or non-numeric the cap defaults to **6**.
- Use `S=1`, `M=2`, `L=3` point mapping.
- The cap is advisory (a warning, never an error). Record the rationale in `assets/decisions.md` when a plan raises it.

## Offline package batching (autonomous container/sandbox plans)

- When a plan adds third-party packages and runs in a sealed runtime (container/sandbox), each new package discovered mid-run triggers an offline **rebundle** round-trip: the runtime commits the manifest, the host regenerates + pushes the lockfile, then relaunches.
- Batch all package-adding steps (NuGet `dotnet`, npm) into a **single early phase** so the rebundle round-trip fires at most once instead of once per package.
- Mirror the batched packages in the `<!-- expected-packages: dotnet:<list>; npm:<list> -->` header marker (use `none` when none).

## State anchor and validator cadence

- Set/update the stage anchor with `Set-PlanStage.ps1 -PlanFile <plan.md path> -Stage drafted` after drafting (never hand-edit `<!-- cip-stage: ... -->`).
- Re-run `Test-Plan.ps1 -Stage Draft` after drafting and after each DR round.

## Capture (`assets/logs/capture.md`)

Durable interview/assumption notes are written **script-only** via `Add-WorkflowNote.ps1 -Kind Capture`; the script resolves the log path itself (`assets/logs/capture.md`, or the plan-folder root for legacy plans), so pass `-PlanDir` (it owns the `## Capture` header, the `No entries for this phase.` placeholder, placeholder-replace, and free-text sanitization):

```powershell
# initialize the phase section (no -Message)
pwsh -NoProfile -File .github/skills/cip/scripts/Add-WorkflowNote.ps1 -Kind Capture -PlanDir <plan-folder> -Phase <N>
# record an interview decision/assumption
pwsh -NoProfile -File .github/skills/cip/scripts/Add-WorkflowNote.ps1 -Kind Capture -PlanDir <plan-folder> -Phase <N> -Step <source-step> -Src note -Concern architecture-patterns -ReviewType none -Message "interview: <decision or assumption>"
```

Initialize the section and commit the capture log by explicit filename at phase start even if empty; commit again when entries are appended. Missing required sections/placeholders fail loud; an intentionally empty `No entries for this phase.` stays valid.

Architecturally-significant decisions also belong in the plan's `assets/decisions/*.md` records. When the `architecture-notes` plugin is installed, those decisions are harvested into proposed ADRs at plan finalization (via `/uan` / the arch-notes **adr-harvest** operation) — quarantined `reviewed: false` until a human promotes accepted ones into the auto-loaded architecture tier.

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
