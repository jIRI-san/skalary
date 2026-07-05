---
description: Architecture-tests runner — the freshness-bound receipt model, failure-taxonomy × maturity gate matrix, human-only lock gate, pluggable deterministic adapters, advisory semantic-eval providers, and how the arch: evidence marker verifies receipts without executing toolchains. Load when working on plugins/architecture-tests/**, the arch runner/receipt scripts, or arch: gate enforcement.
globs:
  - plugins/architecture-tests/**
  - .github/skills/architecture-tests/**
  - scripts/skalary/Invoke-ArchTests.ps1
  - scripts/skalary/ArchReceipt.psm1
  - scripts/skalary/Assert-ArchLock.ps1
  - scripts/skalary/Invoke-ArchAdapter.ps1
  - scripts/skalary/Get-ArchReviewReport.ps1
  - docs/architecture-notes/receipts/**
---

# Architecture Tests

The enforcement half of the guardrails family: it realizes the `architecture-notes` contracts as
**fitness functions** and produces the freshness-bound receipts the plan `arch:<ContractId>` marker
reads. It never enforces on its own — a receipt attests a run happened at a recorded tree-state; the
trust anchor is still the human-authored contract + commit (see
[architecture-notes.design.md](architecture-notes.design.md)).

## Architecture

| Piece | Location | Role |
|---|---|---|
| Runner | `scripts/skalary/Invoke-ArchTests.ps1` | Mints one receipt per configured check under `docs/architecture-notes/receipts/` |
| Shared core | `scripts/skalary/ArchReceipt.psm1` | **Single source of truth** shared by the runner (producer) and the `arch:` marker (verifier) |
| Lock gate | `scripts/skalary/Assert-ArchLock.ps1` | Lock-before-execute authority (REQ-18) |
| Adapter files | `plugins/architecture-tests/scripts/adapters/*.Adapter.ps1` | Deterministic-framework adapters (NetArchTest, ts-arch) — **plugin-owned**; dispatched by `scripts/skalary/Invoke-ArchAdapter.ps1` |
| Providers | `plugins/architecture-tests/scripts/providers/*.ps1` | Semantic-eval (LLM) seam — **plugin-owned** |
| Review report | `scripts/skalary/Get-ArchReviewReport.ps1` | Reuses the `arch:` verifier so a schema-only review can't false-green |
| Config | `arch-test-config.json` (`arch-test-config.schema.json`) | Binds each contract → adapter + targets |
| Receipt | `docs/architecture-notes/receipts/<id>.arch-receipt.json` (`arch-test-receipt.schema.json`) | `verdict`, `ran`, `parentCommit`, `sourcesHash`, `adapter`, `maturity`, `findings`, `lockDecision` |

`ArchReceipt.psm1` exports the drift-proof primitives: `Get-ArchTestSourcesHash` (canonical
content hash over contract + binding + targets), `Resolve-ArchEffectiveMaturity`,
`Get-ArchGateOutcome` (the taxonomy × maturity matrix), and `Read-ArchReceipt` (pure-parse + schema).

## Key Patterns

- **Two distinct integrity mechanisms — don't conflate them.**
  - **Freshness** (`sourcesHash`, checked by the `arch:` marker at plan time): content-hashes
    `contractPath + targets` and folds `spec` / `testProject` / `adapter` / `provider` / `maturity`
    as **identity strings**. So *repointing* a spec/testProject/adapter invalidates the receipt, but
    *editing their content* does not; committing the receipt does not self-invalidate it.
  - **Lock body** (`lockedBodySha256`, enforced by the runner's `Assert-ArchLock` gate at
    **execution**, not by the `arch:` marker): hashes the **whole reviewed body** — a `.csproj`
    testProject's entire project dir, not the leaf — so rewriting reviewed `.cs` assertions is caught
    on the next runner run as `lock-invalidated`. The plan marker never recomputes the lock body.
- **Producer/verifier share one module.** The runner and the `arch:` marker both go through
  `ArchReceipt.psm1`, so the gate the runner writes and the gate the marker reads can never drift.
- **`arch:` marker is pure-parse + trust-anchored.** Verification reads the receipt and re-derives
  `adapter` + `maturity` from the **trusted config/contract**, never from the receipt's own fields
  (those are gate-steering inputs — trusting them is a false-green hole). `verdict`/`ran` are the
  reviewer-enforced residual.

## Design Decisions

- **Failure taxonomy × maturity is the core gate.** Verdicts are `pass` / `fail` /
  `skip-absent-toolchain` / `error`. For **`locked`**, only `pass` greens — `fail`, `error`, **and**
  `skip-absent-toolchain` all block (an env without the toolchain is never a silent pass). `draft` /
  `provisional` warn-only on any non-`pass`. This closes the bypass where an attacker/flaky harness
  converts a `fail` into an `error` and ships.
- **LLM verdicts are advisory in the gate — always.** A `semantic-eval` check never hard-blocks
  regardless of maturity; `Get-ArchGateOutcome -Adapter semantic-eval` maps it to advisory. It reads
  untrusted contract prose (never an executable body), so it bypasses the lock-body gate by design.
- **Lock-before-execute (human-only).** Only a `locked` contract whose body hash verifies runs;
  `draft` bodies **skip** (never false-green); a mutated locked body is `lock-invalidated → error`
  (blocks). An autonomous run may propose a lock but the runner honors `locked` only when the
  promoting commit is human-authored.
- **The adapter/provider FILE SET is plugin-owned — the reason `/ci` references, not bundles, the
  runner.** The runner (`Invoke-ArchTests.ps1`), the shared core (`ArchReceipt.psm1`), the lock
  authority (`Assert-ArchLock.ps1`), and the adapter dispatcher (`Invoke-ArchAdapter.ps1`) are all
  `scripts/skalary/` bundles (canonical there, bundled into `architecture-tests`). What is
  plugin-owned is the concrete adapter/provider **file set** under
  `plugins/architecture-tests/scripts/{adapters,providers}/**` — `NetArchTest.Adapter.ps1`,
  `TsArch.Adapter.ps1`, and the semantic-eval providers (`dependency-cruiser` is a **registered
  adapter id with no shipped implementation** → resolves to `skip-absent-toolchain`). That file set
  can't be bundled into `ci` without forking a second source of truth, so `/ci` invokes the
  **installed** runner via a gated bare reference (mirrors the `Get-ArchReviewReport.ps1` pattern).
  See [plugin-registry.design.md](plugin-registry.design.md) and
  [plan-workflow.design.md](plan-workflow.design.md).
- **Structural vs real run split.** `scripts/validate.ps1` + `npm test` stay dependency-free — they
  pure-parse receipts for presence/consistency and never shell `dotnet`/`npm`/`vitest`. Real
  toolchain runs are **opt-in and `/ci`-homed** (like the eval harness's `-IncludeLlm`).
- **Semantic-eval provider seam.** `Invoke-SemanticEvalProvider -ProviderName <custom|mock|null|waza>`
  → strict JSON `{provider,status,findings,artifacts}`. `custom` targets the copilot judge with a
  dedicated credential target, deny-by-default (no `--allow-all`), child-scoped token, and timeout;
  `mock`/`null` prove swappability; `waza` is documented until its schema is pinned (it hard-returns
  `skip-absent-toolchain`). Untrusted arch
  text is GUID-fenced + boundary-token-neutralized + strict-JSON-only (out-of-taxonomy → `error`).
- **Review surfaces the receipt, not just the schema.** `Get-ArchReviewReport.ps1` reuses the
  `arch:` verifier per contract; a `locked` contract whose receipt is missing/stale/malformed/non-
  `pass` is a **blocking** finding, an unchecked locked contract is a **coverage gap**, and a lock
  promoted by a non-human commit is flagged for re-review.

## Constraints

- **Containment honesty.** `--ignore-scripts` / `--locked-mode` disable *install* lifecycle scripts
  only; `vitest`/`dotnet test` still execute third-party framework code in-process. Real runs
  execute in the documented **non-containing sandbox** until the reserved container backend exists —
  never claim containment.
- **Never trust receipt self-describing fields** (`adapter`/`maturity`) for the gate decision;
  derive from config/contract and cross-check.
- **The runner performs no real toolchain execution in the structural path** and is safe to
  dot-source (functions only).
