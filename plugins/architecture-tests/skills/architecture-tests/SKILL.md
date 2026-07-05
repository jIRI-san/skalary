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

## Lock-before-execute gate

Contract-derived test bodies are **never** executed until the contract is human-reviewed and `locked`.
`Assert-ArchLock.ps1` is the single canonical authority for lock state:

- **Body hash** — `Get-ArchLockedBodyHash` computes the canonical `lockedBodySha256` over the reviewed test
  body. For a `.csproj`/`.vbproj`/`.fsproj` test project the whole project **directory** is hashed (the full
  source closure `dotnet test` compiles), so rewriting a reviewed `.cs` assertion after lock invalidates it;
  a single `ts-arch`/`dependency-cruiser` spec file is hashed as a leaf. Never-committed build outputs and
  VCS folders (`bin`, `obj`, `node_modules`, `.vs`, `.git`) are excluded (case-insensitive directory-segment
  match) so a build run after lock time does not invalidate the lock. The lock gate re-verifies by RECOMPUTE (never
  hex-presence) immediately before execution. A locked contract whose recomputed body hash does not match its
  recorded `lockedBodySha256` — or whose body resolves to zero files — enters an explicit `lock-invalidated`
  state that **blocks** and that review flags as drift.
- **Human-only transitions** — every maturity transition touching `locked` (draft→locked promotion,
  locked→draft demotion) is honored only from a human context. Autonomy is detected by a **concrete signal**
  (`SKALARY_ARCH_AUTONOMOUS`/`SKALARY_AUTOPILOT`/`COPILOT_AUTOPILOT` env var, or an explicit flag), never
  agent self-assessment. An autonomous run may only record a promotion **proposal**
  (`New-ArchPromotionProposal`); it may not mutate lock state.
- **Write-gate** — a `locked` write lacking a verified human signal is refused (`Test-ArchLockWriteAllowed`).

## Adapters

Deterministic adapters are pluggable behind `Invoke-ArchAdapter.ps1`. Each adapter is a
`scripts/adapters/<Name>.Adapter.ps1` exposing `Invoke-<Name>Adapter -Context @{...}` and returning the
strict result contract `{ status; ran; findings[]; artifacts[] }` (status ∈ `pass`/`fail`/`skip-absent-toolchain`/`error`).
`Invoke-ArchTestAdapter` runs the lock gate first, so only a locked, hash-verified body ever reaches an
adapter; draft bodies skip and a mutated locked body errors. The NetArchTest (C#) adapter runs a reviewed
`dotnet test` project and parses its TRX into the result contract; it emits `skip-absent-toolchain` when the
dotnet toolchain is absent. The ts-arch (TypeScript) adapter runs a reviewed `vitest` spec by invoking the
locally-installed `node_modules/vitest/vitest.mjs` **directly via node** (never `npm exec`, which can auto-fetch
from the registry and mangles the `--outputFile` arg), after a deterministic `npm ci --ignore-scripts` from a
**committed** `package-lock.json` (a project without one skips rather than running unpinned), and parses the
JUnit result; a `<skipped>`/`it.todo` assertion or an abnormal vitest exit is never a green. It emits
`skip-absent-toolchain` when node/npm is absent. New adapters need no dispatcher change.

## Semantic-eval provider seam (advisory LLM)

The `semantic-eval` adapter is an **advisory** LLM layer behind a concrete, name-dispatched provider seam
(`scripts/providers/SemanticEvalProvider.ps1`):

```
Invoke-SemanticEvalProvider -ProviderName <custom|mock|null|waza> -ContractPath <p> -TargetRoot <p> [-ConfigPath <p>] [-CredentialTarget <name>]
  -> { provider; status; findings[]; artifacts[] }   # status ∈ pass/fail/skip-absent-toolchain/error
```

- **Advisory in the gate ALWAYS.** An LLM verdict never hard-blocks CI regardless of maturity — a
  `semantic-eval` check maps to `pass` (real pass) or `warn` (anything else), never `block`. Deterministic
  adapters keep the locked hard-gate; the LLM only informs.
- **Swappable, two implementations ship.** `custom` (copilot-CLI judge, dedicated credential target) and
  `mock`/`null` (deterministic, no credential, no LLM) prove the seam is backend-agnostic. `waza` is
  **documented but not implemented** (its `eval.yaml` schema is not yet pinned) and reports
  `skip-absent-toolchain`; adding it is a drop-in `Waza.Provider.ps1` + `provider: waza`, not a runner change.
- **Dedicated credential, skip-not-error.** The provider reads its token from a dedicated Credential Manager
  target (`credentialTarget`, default `skalary-arch-semantic-eval`) isolated from the eval harness. An unset
  or missing credential, or an absent copilot CLI, yields `skip-absent-toolchain` — never `error`, never a
  false pass.
- **Untrusted-text hardening.** Contract prose is UNTRUSTED. Before it reaches a model it is wrapped in
  per-invocation **GUID-suffixed boundary fences**, **boundary-token neutralized** (any sentinel — even a
  guessed guid — is stripped), and the model must return **STRICT JSON only**; any non-JSON, out-of-taxonomy,
  or unparseable verdict collapses to advisory `error`. Contract text is never executed.

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

The runner bundles two canonical helpers beside it — the lock authority
`.github/skills/architecture-tests/scripts/Assert-ArchLock.ps1` and the adapter dispatcher
`.github/skills/architecture-tests/scripts/Invoke-ArchAdapter.ps1` — and dot-sources them automatically.

For each check the runner:

1. Computes the canonical `sourcesHash` over the contract definition, its binding fields, and the target
   sources (add/edit/delete-sensitive; repointing an adapter/spec/testProject also invalidates it).
2. Records the parent commit (`git rev-parse HEAD`).
3. Runs the bound adapter behind the lock gate. The **NetArchTest** (C#) deterministic adapter is wired: a
   `locked`, hash-verified body runs a real `dotnet test` (see `evals/fixtures/netarchtest/` for a committed
   example). When the adapter's toolchain is absent, or no deterministic adapter / `semantic-eval` provider is
   configured, the check resolves to `skip-absent-toolchain` (`ran: false`) — which is **never** a pass for a
   locked contract.
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
`generatedAt`, plus optional `findings`, `artifacts`, and `lockDecision`
(`execute`/`skip-not-locked`/`lock-invalidated`) so review can distinguish a deliberate draft skip from an
absent toolchain and see lock drift. Do not hand-edit receipts; regenerate them by re-running the runner.

## Review report

The `architecture-notes` **review** operation folds these receipts into its tier report via
`.github/skills/architecture-tests/scripts/Get-ArchReviewReport.ps1` (bundled with this plugin) — a
**read-only pure-parse** report (never executes a toolchain). For every contract in the config it reuses the
SAME verifier the `arch:` evidence marker uses (`Invoke-PlanArchEvidence`), so the review is **never laxer
than the CI gate** (it can never false-green; being opt-in-agnostic and always at crosscheck strictness, it
may be stricter): a **locked** contract whose receipt is missing / stale / malformed / non-`pass` surfaces as
a **blocking** finding (a schema-only review can never false-green a failing or absent locked contract), while
`draft`/`provisional` and `semantic-eval` are advisory **only once a receipt exists and passes freshness**; a
`lock-invalidated` receipt is flagged as drift.

```
pwsh -NoProfile -File .github/skills/architecture-tests/scripts/Get-ArchReviewReport.ps1 -RepoRoot .
```

Exit is non-zero when any locked contract has a blocking finding. Locked promotions must still be audited
against the promoting commit's **authorship** (human-authored, per the write-gate) and every locked contract
reconciled against a config check (an unchecked locked contract has no fitness function) — the on-disk
`maturity` field is not trusted on its own.
