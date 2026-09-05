# Intent

Preliminary context captured by /cep; /cip must confirm and refine it.

## Goal

Establish a simple local-only operating baseline for Skalary: no hosted workflows, no routine
whole-suite runs, human-readable internal artifacts, and focused commands that make skill changes
cheap and understandable.

## Desired outcome

The repository is immediately usable without GitHub Actions or a later cleanup phase. Every active
gate, test, JSON path, design note, and architecture contract has one explicit owner and one
keep/transfer/delete disposition. Shared rules are small enough for the three subsystem children to
apply directly.

## Success signals

- `.github/workflows/` and workflow-only machinery are absent, and active guidance prohibits adding
  hosted pipelines.
- Routine validation requires explicit plugin scope, targets under 30 seconds per command, reports a
  distinct result above 60 seconds, and cannot select the full repository implicitly.
- The full suite remains available only through a separate explicit operator-only path.
- Every unaffected-plugin test is justified by current user behavior, an external format, or a
  high-impact regression; uncertain tests are decided by the operator.
- One inventory assigns every active JSON path, affected contract/note, gate, and test to one owner.
- VS Code and Copilot CLI choices provide equivalent context plus `effort: 1-10` and
  `complexity: 1-10`.
- A short RFC ends with operator-approved budgets for agent calls, model roles, context, and
  instruction size.

## Non-goals

- Reworking CR/DR, plan/autopilot execution, SI/PFB, or plugin lifecycle internals owned by later
  children.
- Preserving internal JSON, receipt, workflow, tier, profile, or compatibility formats.
- Adding replacement hosted automation, hooks, policy engines, or a new generic framework.
- Optimizing for untrusted contributors or multi-operator coordination.

## Definition of done

- The repository operates locally after this child lands, every baseline-owned deletion and
  disposition is complete, focused validation is usable, and later children can implement their
  assigned rows without reopening classification or relying on a final sweep.
