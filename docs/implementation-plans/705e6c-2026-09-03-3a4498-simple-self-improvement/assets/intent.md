# Intent

Preliminary context captured by /cep; /cip must confirm and refine it.

## Goal

Replace `/si`, `/pfb`, and proposal harvest with the smallest useful interactive flow: read recent
fenced lessons, show cited proposals with enough context, and apply only changes the operator selects.

## Desired outcome

Self-improvement is a bounded local interaction, not a durable service. It consumes the recent-learning
Markdown produced by `367e9a`, presents equivalent informed choices in VS Code and Copilot CLI, and
writes only selected local instruction/design-note changes through a direct allowed-root check.

## Success signals

- One run reads only the bounded fenced learning artifact from `367e9a`.
- Every proposal cites its source and gives enough context to decide, including
  `effort: 1-10` and `complexity: 1-10`.
- The operator can select individual proposals in VS Code and through an equivalent CLI interaction.
- Only selected changes are applied, and only under explicit allowed roots; workflow paths are always
  rejected.
- Prompt-injection treatment and focused write-scope refusal tests remain.
- Durable store, CAS, repair, receipts, schemas, remote PR lifecycle, and harvest orchestration are
  absent.

## Non-goals

- Reading the historical plan corpus or building another history index.
- Capturing learning during review or plan execution; child `367e9a` owns that producer.
- Automatically applying all proposals, managing remote PRs, or persisting proposal lifecycle state.
- Supporting untrusted contributors or multi-operator coordination.

## Definition of done

- `/si` and `/pfb` provide a complete bounded proposal-and-apply interaction in both supported hosts,
  retain the two essential content/write guards, remove obsolete state machinery, and validate through
  a small focused deterministic test set.
