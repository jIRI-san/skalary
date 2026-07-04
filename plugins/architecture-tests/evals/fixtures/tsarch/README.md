# ts-arch fixture (real deterministic adapter run)

This fixture proves the ts-arch (TypeScript) adapter runs a **real** `vitest` architecture spec and reports a
deterministic `fail` when a locked architecture contract is violated. It backs the opt-in eval
`Adapter-TsArch-DetectsViolation` in `../../architecture-tests.Tests.ps1`.

## Layout

| Path | Role |
|---|---|
| `src/domain/order.ts` | Domain file. **Intentionally** imports `src/infrastructure/database.ts` — the violation. |
| `src/infrastructure/database.ts` | Infrastructure file the Domain layer must not depend on. |
| `tests/arch.spec.ts` | Human-owned, reviewed ts-arch assertion (`domain -> infrastructure` forbidden via `filesOfProject().inFolder("domain").shouldNot().dependOnFiles().inFolder("infrastructure")`). This single spec is the **locked body** the contract hashes (a leaf). |
| `arch-contract.json` | The `locked` contract. `lockedBodySha256` is the canonical `Get-ArchLockedBodyHash` digest over `tests/arch.spec.ts`. |
| `package-lock.json` | Committed lock file. Install is deterministic via `npm ci --ignore-scripts`. |
| `vitest.config.ts` / `tsconfig.json` | Minimal vitest + TypeScript config (`globals: true` so the `tsarch/dist/jest` matcher registers). |

The adapter only ever **executes** the reviewed spec; it never derives or compiles test code from the contract
prose. The contract body hash covers the committed spec only — `node_modules/` and build outputs are excluded so
an install after lock time does not invalidate the lock. `ts-arch`'s `inFolder(name)` matches a folder **name**
(a path segment), not a slash path — the spec uses `inFolder("domain")` / `inFolder("infrastructure")`.

## Sandbox model (container backend NOT built)

There is no container isolation here. The fixture runs **directly on the host** in a documented, non-containing
sandbox: it is a self-contained project tree that references only public npm packages pinned in the committed
`package-lock.json`, installed with `npm ci --ignore-scripts`, and asserts against its own source files. It never
touches the surrounding repository. Container-backed isolation is an explicit non-goal of this phase.

The adapter invokes the locally-installed `node_modules/vitest/vitest.mjs` **directly via node** — never through
`npm exec` (which can auto-fetch from the registry and mangles the `--outputFile` arg) — so the vitest execution
never reaches the network. The one-time `npm ci --ignore-scripts` install is lockfile-pinned + integrity-checked
but may fetch tarballs from the registry on a cache miss.

## Running it (opt-in only)

Structural evals and `npm test` never shell `node`/`npm`/`vitest`. The real run is opt-in so CI stays hermetic:

```powershell
# 1. install deterministically from the committed lock file
npm ci --ignore-scripts

# 2. run the opt-in eval (default: skipped)
$env:SKALARY_ARCH_REAL_RUN = '1'
Invoke-Pester -Path ../../architecture-tests.Tests.ps1 -Output Detailed
```

Expected: the adapter returns `status = fail`, `ran = true`, with a finding naming `src/domain/order.ts`.

To regenerate the lock file after a deliberate dependency change, run `npm install --ignore-scripts` (without
`ci`), review the diff, and recompute `lockedBodySha256` with
`Get-ArchLockedBodyHash -Paths tests/arch.spec.ts -RepoRoot .`.
