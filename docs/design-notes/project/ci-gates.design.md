---
description: Local-first focused validation commands, explicit broad operator routes, scope confinement, and timeout behavior.
globs:
  - scripts/validate.ps1
  - scripts/skalary/Run-UnitTests.ps1
  - scripts/skalary/Test-Evals.ps1
  - scripts/skalary/Invoke-WazaEvals.ps1
  - package.json
  - .autopilot.json
---

# Local Validation Commands

Skalary has no repository-owned hosted workflow. Validation is local and direct. Adding a
`.github/workflows/` file is outside the project operating model; do not replace removed workflows
with another hosted pipeline or an aggregate local gate.

## Routine focused commands

Every routine deterministic entry point refuses omitted, invalid, escaping, linked, or conflicting
scope with `FocusedScopeRequired` (exit `12`). Selection never retries or widens.

| Concern | Command | Selected work |
|---|---|---|
| Unit | `scripts/skalary/Run-UnitTests.ps1 -TestPath <tests/...Tests.ps1>` | Only named test files; `-TestName` or `-EvidenceTestId` may narrow further |
| Structural eval | `scripts/skalary/Test-Evals.ps1 -Plugin <plugin>` | Only `plugins/<plugin>/evals/**/*.Tests.ps1`; global required-case completeness is reserved for the explicit broad run |
| Syntax validation | `scripts/validate.ps1 -Path <file-or-directory>` | Only selected PowerShell and JSON files below the repository root |

Focused paths are canonicalized before execution and every existing component must be a regular,
non-link path. Output paths are repository-confined and validated before creation. A selected command
runs in one directly launched PowerShell child. The target is under 30 seconds. A command completing
from 30 seconds to below 60 emits `FocusedSlow` only after completion and preserves the child verdict.
Tests may supply bounded shorter warning and timeout values. No state, retry, fallback, or recovery
service exists.

## Supervision, deadline, and containment

Supervision lives in `scripts/skalary/internal/FocusedSupervision.ps1`, which the three public commands
invoke by path. It starts a clean PowerShell child through `System.Diagnostics.Process`, sends bound
request data on stdin, and waits against one wall-clock deadline. Exceeding the deadline calls
`Process.Kill(true)`, waits briefly for shutdown, reports completed output, and exits `13` with
`FocusedTimeout`. The public commands expose no worker/bypass switch or environment protocol.

**Deliberate simple-over-safe tradeoff:** this is a timeout, not a sandbox. `Process.Kill(true)` covers
the current child process tree on Windows and Linux without native interop, job objects, process groups,
PID sweeping, services, or durable state. A process that deliberately detaches and is reparented before
the deadline may escape. That risk is accepted for this single-user repository with trusted local tests;
revisit it only if the threat model changes. Child-start failure exits `14` with
`FocusedWorkerStartFailed`.

`package.json` keeps only focused `build` and `test` defaults needed by `.autopilot.json`; neither is an
aggregate or broad alias. Agents and skills may run these focused defaults or direct focused scripts.
They do not invoke broad or premium routes.

## Direct operator routes

`-FullRepository` is the sole broad selector for `Run-UnitTests.ps1`, `Test-Evals.ps1`, and
`validate.ps1`. It is available only as an explicit direct script switch: there is no npm alias,
agent caller, identity check, tier, budget, or authorization layer.

Waza is a separate premium, nondeterministic route:

```powershell
scripts/skalary/Invoke-WazaEvals.ps1 -Plugin <plugin>
```

It rejects omitted, malformed, nonexistent, linked, and `-ChangedOnly` scope before tool provisioning,
token resolution, or output creation. There is no Waza package or skill alias.

## Retained broad behavior

The direct broad switches remain operator diagnostics, not required gates. `validate.ps1
-FullRepository` performs repository parse and local consistency checks. `Test-Evals.ps1
-FullRepository` verifies every ID in `tools/structural-eval-required.md`. `Run-UnitTests.ps1
-FullRepository` directly selects all `*.Tests.ps1` files under `tests/`; it has no tier, profile,
coverage, or runtime-budget machinery.

## Evidence

`test:FocusedCommands.Contract` proves scope refusal/confinement and selected-only behavior.
`test:FocusedCommands.SupervisionIsNotSelectable` proves the public surface has no bypass, then exercises
one passing run, one warning, one zero-selection failure, and one timeout that terminates a descendant.
`test:LocalFirst.BaselineContract` proves workflows and implicit broad/premium callers are absent, the
explicit direct switches remain, and Waza rejects an intermediate linked directory.
`test:LocalFirst.ActiveAuthorityReferences` keeps active architecture notes from asserting authority the
removed workflows carried.
