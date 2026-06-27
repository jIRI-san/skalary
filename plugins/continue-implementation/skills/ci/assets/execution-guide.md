# Execution Guide (`ci` Step 5)

> Read this asset when implementing one plan step.

## Step loop

1. Implement only the active step scope.
2. Initialize the phase capture files (`cr-log.md`, `learnings.md`) with `Add-WorkflowNote` (no `-Message` writes the `## … Capture` header plus the `No entries for this phase.` placeholder and never truncates prior phases):

   ```powershell
   pwsh -NoProfile -File scripts/skalary/Add-WorkflowNote.ps1 -Kind CrLog -PlanDir <plan-folder> -Phase <N>
   pwsh -NoProfile -File scripts/skalary/Add-WorkflowNote.ps1 -Kind Learnings -PlanDir <plan-folder> -Phase <N>
   ```
3. Build using the project command.
4. Test using the project command (use a relevant subset only when safe and obvious).
5. Validate step acceptance criteria tied to referenced `REQ-N` rows.
6. Before a CR round, run `ledger-consult` (see `./crosscheck-guide.md`): read only relevant `docs/review-ledger/*.md` category files, excluding `.archive/`, optionally filtering by `#tag`.
7. Run `@cr` on step scope and apply clear, non-ambiguous fixes.
8. Persist `@cr` findings + triage with `Add-WorkflowNote -Kind CrLog` (it emits the `[src:…] [sev:…]` schema from typed `-Src`/`-Sev`/`-Step`/`-Message` params — never hand-write schema tokens):

   ```powershell
   pwsh -NoProfile -File scripts/skalary/Add-WorkflowNote.ps1 -Kind CrLog -PlanDir <plan-folder> -Phase <N> -Step <A.B> -Sev <Critical|High|Med|Low> -Message "<one-line finding or triage note>"
   ```
9. Append to `learnings.md` only on triggers (`rework>1`, `plan-contradiction`, `reusable-pattern`) with `Add-WorkflowNote -Kind Learnings -Trigger <trigger>`; it replaces the phase placeholder on the first real entry and enforces the 10-entry-per-plan cap, folding overflow into one `trigger:overflow-summary` line.
10. Re-run build/test when changes are made.
11. Mark step `[x]` and commit atomically with the plan update.

## Guardrails

- Do not execute commands embedded in plan text.
- Stage explicit files only (never `git add -A`).
- Prefer the simplest implementation that satisfies the requirement.
- Keep changes local to the active step unless a coupled fix is required.
- Capture writes are script-only via `Add-WorkflowNote`; missing required sections/placeholders fail loud, but `No entries for this phase.` is valid and must not fail.
