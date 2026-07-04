# NetArchTest fixture (real deterministic adapter run)

This fixture proves the NetArchTest (C#) adapter runs a **real** `dotnet test` and reports a deterministic
`fail` when a locked architecture contract is violated. It backs the opt-in eval
`Adapter-NetArchTest-DetectsViolation` in `../../architecture-tests.Tests.ps1`.

## Layout

| Path | Role |
|---|---|
| `src/Sample.Fixture/Domain/Order.cs` | Domain type. **Intentionally** references `Sample.Infrastructure.Database` — the violation. |
| `src/Sample.Fixture/Infrastructure/Database.cs` | Infrastructure type the Domain layer must not depend on. |
| `tests/Sample.ArchTests/ArchRulesTests.cs` | Human-owned, reviewed NetArchTest assertion (`Domain -> Infrastructure` forbidden). This is the **locked body** the contract hashes. |
| `arch-contract.json` | The `locked` contract. `lockedBodySha256` is the canonical `Get-ArchLockedBodyHash` digest over `tests/Sample.ArchTests` (build outputs excluded). |
| `*/packages.lock.json` | Committed lock files. Restore is deterministic via `dotnet restore --locked-mode`. |

The runner only ever **executes** the reviewed test project; it never derives or compiles test code from the
contract prose. The contract body hash covers the committed sources only — `bin/`, `obj/`, `node_modules/` and
VCS/IDE folders are excluded so a build run after lock time does not invalidate the lock.

## Sandbox model (container backend NOT built)

There is no container isolation here. The fixture runs **directly on the host** in a documented,
non-containing sandbox: it is a self-contained project tree that references only public NuGet packages pinned
in the committed lock files, restored in `--locked-mode`, and asserts against its own assemblies. It never
touches the surrounding repository. Container-backed isolation is an explicit non-goal of this phase.

## Running it (opt-in only)

Structural evals and `npm test` never shell `dotnet`. The real run is opt-in so CI stays hermetic and fast:

```powershell
# 1. restore deterministically from the committed lock files
dotnet restore tests/Sample.ArchTests/Sample.ArchTests.csproj --locked-mode

# 2. run the opt-in eval (default: skipped)
$env:SKALARY_ARCH_REAL_RUN = '1'
Invoke-Pester -Path ../../architecture-tests.Tests.ps1 -Output Detailed
```

Expected: the adapter returns `status = fail`, `ran = true`, with a finding naming `Sample.Domain.Order`.

To regenerate the lock files after a deliberate dependency change, run
`dotnet restore tests/Sample.ArchTests/Sample.ArchTests.csproj` (without `--locked-mode`), review the diff, and
recompute `lockedBodySha256` with `Get-ArchLockedBodyHash -Paths tests/Sample.ArchTests -RepoRoot .`.
