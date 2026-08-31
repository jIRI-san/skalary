# Intent

## Goal

Make the epic-autopilot final-evidence path behave identically on Windows and Linux.

## Desired outcome

The three Windows failures reported at PR #30 head `7a6270e9` pass without weakening
Capture-only publication, exact residue admission, or fail-closed state handling.

## Success signals

- `EpicAutopilot.FinalCrosscheck` accepts canonical Capture content regardless of checkout line endings.
- `EpicAutopilot.NoCheckpointProductionFinalization` retains a valid state path under Windows fixture paths.
- `EpicAutopilot.AbruptEvidenceRecovery` recognizes only the exact permitted Capture residue on Windows.
- Full local Windows build, Fast, Slow, structural eval, and consumer-install gates pass.

## Non-goals

- Reopening or replacing the wrapped `a5ad22` final review.
- Running PlanCrosscheck, archiving `a5ad22`, or claiming it DONE.
- Changing the six-field epic resume-state contract or adding another recovery protocol.

## Definition of done

- The repair is implemented through repository container-autopilot, pushed to PR #30, and all required
  local Windows validation is green while prior review/evidence history remains append-only.
