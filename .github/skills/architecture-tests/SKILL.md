---
name: architecture-tests
description: 'Run architecture-contract checks and emit freshness-bound receipts. Binds each contract to a deterministic (NetArchTest/ts-arch/dependency-cruiser) or advisory semantic-eval adapter, records a parent-commit + sources hash, and maps the failure-taxonomy verdict to a gate outcome that honours contract maturity (locked blocks, draft/provisional warn). Use when validating that an implementation still obeys the human-owned architecture contracts.'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Architecture Tests

Enforce the architecture contracts authored with the `architecture-notes` skill. The human owns the
contracts and the reviewed test projects; agents run the checks and read the receipts. This skill never
authors or promotes a contract — it only executes checks and records evidence.

## Trust model

- The trust anchor is the human-authored git commit + review, NOT the receipt. A receipt attests that a
  run happened at a recorded tree-state; it is not an anti-forgery signature.
- Architecture-note prose is UNTRUSTED input. It is never executed. Only human-owned, reviewed test
  projects/specs run.
- Freshness binds to `sourcesHash` (contract + target sources), not raw HEAD equality — so committing a
  receipt does not self-invalidate it.

## Config

Checks live in an `arch-test-config.json` validated against
`schemas/arch-test-config.schema.json` (scaffolded on init, no-overwrite). Each check binds a
`contractId` to an `adapter`, a `maturity` (`locked` blocks, `draft`/`provisional` warn; defaults to
`draft`), the `contractPath` + `targets` it governs, and — for deterministic adapters — a reviewed
`testProject`/`spec`, or a `provider` for `semantic-eval`.

## Run

Invoke the runner (bundled at its installed path):

```
pwsh -NoProfile -File .github/skills/architecture-tests/scripts/Invoke-ArchTests.ps1 -ConfigPath <arch-test-config.json> -RepoRoot .
```

For each check the runner:

1. Computes the canonical `sourcesHash` over the contract definition, its binding fields, and the target
   sources (add/edit/delete-sensitive; repointing an adapter/spec/testProject also invalidates it).
2. Records the parent commit (`git rev-parse HEAD`).
3. Runs the bound adapter. Until a deterministic adapter or `semantic-eval` provider is wired, the check
   resolves to `skip-absent-toolchain` (`ran: false`) — which is **never** a pass for a locked contract.
4. Emits a receipt (`schemas/arch-test-receipt.schema.json`) under `docs/architecture-notes/receipts/`.

## Verdict taxonomy and gate

`verdict` is one of `pass`, `fail`, `skip-absent-toolchain`, `error`. The gate outcome depends on
contract maturity:

- **locked** — only `pass` greens; `fail`, `error`, and `skip-absent-toolchain` all **block**. Skip is
  never a false-green.
- **draft / provisional** — any non-`pass` **warns** (advisory), so evolving contracts inform without
  blocking.

Grow one locked contract at a time; demotion and re-lock are human-only transitions handled by the
`architecture-notes` write-gate.

## Receipts

Receipts are the sole source of truth the `arch:<ContractId>` evidence marker pure-parses. They live
under `docs/architecture-notes/receipts/<contractId>.arch-receipt.json` and carry `contractId`,
`maturity`, `adapter`, `verdict`, `ran`, `parentCommit` (40/64-hex), `sourcesHash` (64-hex), and
`generatedAt`. Do not hand-edit receipts; regenerate them by re-running the runner.
