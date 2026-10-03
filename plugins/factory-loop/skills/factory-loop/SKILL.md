---
name: factory-loop
description: "Set up and operate a bounded issue-to-production delivery loop with restart-safe local polling, human merge and promotion gates, and a real local demo."
argument-hint: "setup|demo|tick|resume plus an explicit consumer repository path"
user-invocable: true
disable-model-invocation: true
context: fork
---

# Factory loop

Use the [operator guide](./assets/operator-guide.md) for setup, live adapter contracts, scheduler
examples, recovery, and safety limits. Run every command against one explicitly selected repository;
never infer the consumer from the plugin installation directory.

## Setup

Preview, inspect the planned paths and digest, then apply that exact preview:

```powershell
.github/skills/factory-loop/scripts/Setup-FactoryLoop.ps1 -Action preview -RepoRoot .
.github/skills/factory-loop/scripts/Setup-FactoryLoop.ps1 -Action apply -RepoRoot . -ExpectedDigest <digest>
```

Setup writes only missing project-owned files. It never stores credentials or overwrites existing
consumer content. For an idea, use `/cip` to create and confirm a plan; for a prepared plan, verify
its confirmation before ordinary `/ci` admission.

## Local demo

Create a disposable project explicitly outside the consumer working tree:

```powershell
.github/skills/factory-loop/scripts/New-FactoryLoopDemo.ps1 -Action create -DemoRoot <empty-temp-directory> -ConsumerRoot .
```

After committing an application fix on a `feature/*` branch, review the exact source SHA and explicitly
merge it:

```powershell
.github/skills/factory-loop/scripts/New-FactoryLoopDemo.ps1 -Action merge -DemoRoot <demo-directory> -Branch feature/fix-discount -ExpectedSourceSha <reviewed-sha> -ConfirmMerge
```

The demo merge is a real local Git merge. Test and production use the same digest-pinned artifact;
later working-tree changes cannot replace that artifact.

## Tick and resume

`Invoke-FactoryLoopTick.ps1` performs one finite deterministic poll. It never invokes an agent while
waiting. Invoke it again from a personal scheduler or after restart. One active chain per project is
allowed; a missing, malformed, or unidentifiable adapter result pauses the chain instead of guessing
or retrying a write.

Factory repair uses the existing `/ci` launcher only after ordinary initial admission and explicit
repair authorization. The original criteria baseline is revalidated and cannot be edited by repair.
Human PR merge and artifact-specific production approval remain required.
