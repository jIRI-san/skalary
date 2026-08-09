# Design Review Guide (`cip` Step 4)

> Read this asset when running design review. Iterative, **max 3 rounds by default**. Most real issues surface in rounds 1–3; later rounds produce re-discoveries, cross-model contradictions, and increasingly theoretical edge cases that add bulk without value.

## Evolution Log

Create/update `evolution-log.md` in the plan folder (e.g. `docs/implementation-plans/NNN-<slug>/evolution-log.md`). After each DR round, append:
- Round number
- Issues found (brief)
- Issues fixed
- Issues deferred → "Known Plan Issues" section in the plan

DR agents **must be given the evolution log as context** to prevent re-reporting fixed issues or contradicting prior deliberate decisions.

The plan's capture log (`assets/logs/capture.md`; plan-folder root for legacy plans) keeps a separate, durable `## Capture` section for notable/recurring DR findings (not DR-round chronology), written **script-only** via `Add-WorkflowNote.ps1 -Kind Capture` (it owns the header, `No entries for this phase.` placeholder, placeholder-replace, and sanitization):

```powershell
pwsh -NoProfile -File .github/skills/cip/scripts/Add-WorkflowNote.ps1 -Kind Capture -PlanDir <plan-folder> -Phase <N> -Step <source-step> -Src note -Concern <concern> -Requirement <REQ-N...> -ReviewType dr -Message "dr: <notable finding>"
```

Keep capture entries in the capture log only; do not mix them into the DR-round narrative in `assets/evolution-log.md`.

## Simplicity Gate

After each DR round, before applying findings, evaluate:
- Has the plan grown more complex without proportional risk reduction?
- Are findings adding edge-case guards for scenarios that are unlikely in practice?
- Would a simpler approach satisfy the actual user requirement?

Flag overengineering explicitly. Reject findings that optimize for theoretical completeness over practical sufficiency.

## Procedure

1. Invoke `@dr` passing the in-repo plan file path (`docs/implementation-plans/NNN-<slug>/plan.md`) **and** the evolution log. DR always reviews the repo file — never session-memory content.
2. **Surface the findings before touching the plan.** Display the full DR report in chat — the complete numbered findings list (title, severity, models, one-line summary) for *every* finding, not just the ones needing a decision. Then state your triage: which findings you'll auto-apply (clear-cut) and which need a user decision. Never silently apply findings; the user must be able to see every issue raised even when no approval is required.
3. Apply clear-cut findings; for findings that touch an explicit user decision or are ambiguous, ask the user first. Update `assets/decisions.md`. Append a round summary to `assets/evolution-log.md`, record notable/recurring entries to the capture log via `Add-WorkflowNote -Kind Capture`, and commit both by explicit filename.
4. After applying findings, re-run `Test-Plan.ps1` (or `npm run validate-plan`) to confirm the plan still passes structural + evidence integrity.
5. If `@dr` raised **High** or **Critical** findings requiring substantial plan changes, run another round (up to 3 total).
6. After round 3, if issues remain:
   - Record them in a "Known Plan Issues" section at the bottom of the plan.
   - Ask: **"3 DR rounds complete. Remaining issues recorded as Known Plan Issues. Continue reviewing or start implementation?"**
   - Only continue past 3 if the user explicitly requests more rounds.

## State Anchor

After each DR round, set the stage with `Set-PlanStage.ps1 -PlanFile <plan.md path> -Stage dr-round-N` (never hand-edit `<!-- cip-stage: ... -->`) so a resumed session knows where review left off.
