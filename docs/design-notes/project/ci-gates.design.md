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
invoke *by path* and address as an object. Nothing in the focused dispatch is reached by command-name
resolution: the helper invokes no named command at all, resolves the host executable from
`[System.Environment]::ProcessPath` under absolute existing-leaf validation, and encodes the request
with .NET primitives. An alias or function planted in the calling session therefore cannot stand in for
the host lookup, the body path, the request encoder, or the supervisor itself.

One monotonic wall-clock deadline covers process start, the stdin request handoff, root exit, stdout
EOF, and stderr EOF. Root exit is not completion: a root that exits after spawning a descendant which
retains the inherited output pipes still reaches the deadline. No result is read from a wait that did
not complete; after termination a bounded drain reports whatever output did finish. Exceeding the
deadline terminates the owned containment and exits `13` with `FocusedTimeout`, and a killed run never
emits `FocusedSlow`.

Containment is native and owned, with no PID or name sweeping and no durable state, service, or
authorization layer. On Linux the child is launched through a physically validated absolute `setsid`
so it leads its own session and process group — confirmed with a native `getpgid` before the stdin
handshake releases it — and termination is a native negative-PGID `SIGKILL`. On Windows the child is
assigned to a Job Object set kill-on-close, again before the handshake releases it, and termination is
`TerminateJobObject`. Handles are closed and the containment is disposed on every path, so normal
completion leaks no descendant and touches nothing the run did not create. Containment that cannot be
established fails closed: the command exits `14` with `FocusedContainmentUnavailable` rather than
running work it could not terminate. There is no public bypass or test seam for any of this.

`package.json` keeps only focused `build` and `test` defaults needed by `.autopilot.json`; neither is an
aggregate or broad alias. Agents and skills may run these focused defaults or direct focused scripts.
They do not invoke broad or premium routes.

## Direct operator routes

`-FullRepository` is the sole broad selector for `Run-UnitTests.ps1`, `Test-Evals.ps1`, and
`validate.ps1`. It is available only as an explicit direct script switch: there is no npm alias,
agent caller, identity check, or authorization layer. Unit Slow/All modes therefore also require
`-FullRepository`.

Waza is a separate premium, nondeterministic route:

```powershell
scripts/skalary/Invoke-WazaEvals.ps1 -Plugin <plugin>
```

It rejects omitted, malformed, nonexistent, linked, and `-ChangedOnly` scope before tool provisioning,
token resolution, or output creation. There is no Waza package or skill alias.

## Retained broad behavior

The direct broad switches preserve legacy diagnostic capability while later cleanup owns tier,
profile, coverage, and internal-JSON retirement. `validate.ps1 -FullRepository` still performs its
repository parse and local consistency checks. `Test-Evals.ps1 -FullRepository` still verifies every
required structural ID. `Run-UnitTests.ps1 -FullRepository` still derives its selected tier from the
existing tier manifest. These routes are operator diagnostics, not required gates.

## Evidence

`test:FocusedCommands.Contract` proves scope refusal/confinement, selected-only behavior, post-completion
warning, exit `13`, and descendant termination with reduced thresholds. `test:LocalFirst.BaselineContract`
proves workflows and implicit broad/premium callers are absent while the explicit direct switches remain.
`test:LocalFirst.ActiveAuthorityReferences` keeps the active architecture notes from asserting authority
the removed workflows carried.

`tests/skalary/FocusedContainment.Tests.ps1` carries the supervision invariants:
`test:FocusedContainment.NoCommandResolution` parses the helper and proves it invokes nothing by name;
`test:FocusedContainment.PoisonedCommandsCannotRedirect` preseeds both a function and an alias for every
plausible dispatch step and still gets the real verdict; `.LeakyDescendantRootExitTimesOut` and
`.RunningRootTimesOutWithDescendants` prove the single deadline and descendant death across both the
exited-root and still-running-root shapes while an unrelated process survives;
`.CompleteOutputPrecedesSlowWarning` pins complete stdout and stderr ahead of `FocusedSlow`;
`.OwnsDescendantsAcrossRootExit` exercises the real containment on the running platform; and
`.FailsClosedWithoutContainment`, `.FailsClosedWithoutSessionLauncher`, and
`.WindowsJobObjectOwnership` pin the closed failures and the Windows mechanism and its ordering.
