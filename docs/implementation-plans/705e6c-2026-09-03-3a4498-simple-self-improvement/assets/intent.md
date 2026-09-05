# Intent

## Goal

Replace `/si`, `/pfb`, and proposal harvest with the smallest useful interactive flow: read recent
fenced lessons, show cited proposals with enough context, and apply only changes the operator selects.

## Desired outcome

Self-improvement is a bounded local interaction, not a durable service. It consumes the recent-learning
Markdown produced by `367e9a`, presents equivalent informed choices in VS Code and Copilot CLI, and
writes only selected local instruction/design-note changes through direct physical path checks.
`/pfb` remains useful as a stateless delivered-vs-intent comparison and may hand an accepted correction
directly to `/cip`.

## Success signals

- One `/si` run reads only the bounded fenced learning artifact from `367e9a`.
- Every proposal cites its source and gives enough context to decide, including
  `effort: 1-10` and `complexity: 1-10`.
- The operator can select individual proposals in VS Code and through an equivalent CLI interaction.
- Only selected canonical Markdown changes are applied in the current worktree; workflow paths,
  generated copies, executable code, plans, and runtime state are rejected.
- `/pfb` performs its comparison without a queue or other persisted verdict state.
- Prompt-injection treatment and focused write-scope refusal tests remain.
- Durable store, CAS, repair, receipts, schemas, remote PR lifecycle, and harvest orchestration are
  absent.

## Non-goals

- Reading the historical plan corpus or building another history index.
- Capturing learning during review or plan execution; child `367e9a` owns that producer.
- Automatically applying all proposals, creating branches or PRs, or persisting proposal lifecycle
  state.
- Editing generated dogfood copies directly, executable code, workflow/action files, plans, or runtime
  state through `/si`.
- Supporting untrusted contributors or multi-operator coordination.

## Definition of done

- `/si` provides a complete bounded proposal-and-apply interaction in both supported hosts; `/pfb`
  provides a stateless intent comparison and optional correction-plan handoff. Both retain their useful
  trust boundaries, obsolete state machinery is absent, and a small focused deterministic test set
  validates the behavior.
