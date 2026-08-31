---
description: Autonomous plan execution via Copilot CLI — host/container/sandbox modes, auth, orchestration, agent definition
globs:
  - plugins/autopilot/scripts/**
  - plugins/autopilot/devcontainer/**
  - plugins/autopilot/agents/autopilot.agent.md
  - .github/agents/autopilot.agent.md
  - .autopilot.json
  - .autopilot.host.json
  - plugins/autopilot/schemas/autopilot.schema.json
  - plugins/autopilot/schemas/autopilot.host.schema.json
  - scripts/skalary/EpicAutopilot.psm1
  - scripts/skalary/Invoke-EpicAutopilot.ps1
  - scripts/skalary/Invoke-ContainerToolchainGate.ps1
---

# Autonomous Plan Execution

Infrastructure for delegating implementation plan execution to GitHub Copilot CLI running autonomously — in a host worktree, Docker container, or Windows Sandbox.

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│  /ci skill (VS Code) — Autonomous mode          │
│  ├─ selects runtime and execution extent        │
│  └─ reads autopilot SKILL.md → launch.ps1       │
└───────────────────┬─────────────────────────────┘
                    │
┌───────────────────▼─────────────────────────────┐
│  launch.ps1 (entry point)                        │
│  ├─ Validates .autopilot.json                    │
│  ├─ Checks build/test command allowlist          │
│  ├─ Docker/Sandbox pre-flight (mode-specific)    │
│  ├─ Sweeps stale env files                       │
│  ├─ Validates auth (validate-auth.ps1)           │
│  └─ Dispatches to mode-specific orchestrator     │
└───────┬───────────────────┬─────────┬───────────┘
        │                   │         │
┌───────▼───────────┐ ┌────▼────┐ ┌──▼──────────────────┐
│  launch-host.ps1  │ │container│ │  launch-sandbox.ps1  │
│  ├─ git worktree  │ │  .ps1   │ │  ├─ Toolchain cache  │
│  ├─ Per-phase     │ │  ├─ …   │ │  ├─ .wsb generation  │
│  │   copilot CLI  │ │         │ │  ├─ Bootstrap script  │
│  ├─ Live stream   │ │         │ │  ├─ Clone from mount  │
│  └─ Timeout kill  │ │         │ │  ├─ Per-phase CLI     │
│                   │ │         │ │  └─ Final push        │
└───────────────────┘ └─────────┘ └──────────────────────┘
```

### Epic host child launch

`Invoke-EpicAutopilot.ps1` is a host-only wrapper above the existing per-plan launcher. It invokes
`Get-PlanState.ps1 -Epic -Json` with bound arguments and treats that command's `NextChild` as
authoritative; it never parses plans or calls Docker, auth, rebundling, runtime adapters, or child
execution directly. `AUTOPILOT_CONTAINER=true` fails closed before selection or launch.

Selection is serialized through `AtomicStore` and persisted at
`<git-common-dir>/skalary/epic-autopilot.json`. The location is host-owned Git metadata, not
consumer-repository content materialized by plugin installation; the arbitrary `StatePath` seam is
private to the module's test core and is not exposed by the installed production command. The
record has exactly six case-sensitive string fields:

| Field | Meaning |
|---|---|
| `epic` | Canonical six-hex `Get-PlanState.EpicId` |
| `target` | Full commit id resolved from the caller's target Git ref at selection |
| `currentChild` | Canonical six-hex `Get-PlanState.NextChild.Id` |
| `branch` | Reserved per-child branch, `feature/<NextChild.FolderName>` |
| `run` | Canonical GUID allocated once for this sequential run |
| `outcome` | `selected`, `running`, `awaiting-merge`, `invocation-failed`, or `exit:<0..255>` |

A fresh process resumes `selected` or reconciles `running` only when canonical epic, resolved target
commit, exact `NextChild`, and derived branch still match. Malformed state or a different epic fails
loudly before mutation. Non-success terminal records (`invocation-failed` and nonzero `exit:*`) are
immutable retry stops even when the target or graph changed; they never skip to a sibling. A null
`NextChild` with no state returns a typed complete or blocked stop without creating a record.

Under the `AtomicStore` lock, the wrapper resolves the target commit first, requires the repository
worktree to be clean with HEAD at that exact commit, and only then invokes `Get-PlanState`. It creates
or resumes `selected`, acquires a run-scoped host lease, then CAS-transitions that same run to
`running`. The short state lock is released before the blocking launcher call, while the run lease
stays held through image preparation, container execution, transcript extraction, and terminal-state
publication. Resume treats either a live host lease or active deterministic container as running, so
container absence alone cannot overwrite a launcher that is still starting or finishing. The launcher
runs once as a separate PowerShell process from repo root,
using `ProcessStartInfo.ArgumentList` with exact arguments `-PlanSlug <NextChild.FolderName> -Mode
whole-plan -Runtime container -Branch <normalized-target-branch> -ExpectedStartCommit
<persisted-target-commit> -Run <persisted-run>`. `HEAD` normalizes to its local branch and detached
HEAD is refused; `refs/heads/` is stripped and other Git object expressions are rejected. The first
epic container initializes an empty repository, fetches the selected branch once into `FETCH_HEAD`,
proves that object equals the persisted commit, rejects any existing remote work branch, and creates
the work branch directly from the verified object. Existing callers that omit `-ExpectedStartCommit`
retain ordinary launch behavior. Only a later exit-43 attempt inside the same host launcher invocation
receives the internal retry flag and may fetch/resume the remote work branch; a fresh invocation cannot
claim that provenance. After it returns, the wrapper reacquires the lock and CAS-transitions the same
`running` generation: zero becomes `awaiting-merge`, while nonzero becomes `exit:<1..255>`. The
per-plan launcher's zero is the authoritative close proof: its existing chain requires canonical
evidence and review receipts, an exact committed archive transition, and pre-probe publication of
the expected work branch. Final close then proves the checked-out branch and full local `HEAD`,
exactly one same-OID `refs/heads/<work-branch>` on origin, and exactly one typed open PR row whose
head name/OID match. `EXPECTED_START_COMMIT` is the epic-provenance signal: when it is present,
`REPO_BRANCH` is mandatory and must match the PR base, including on trusted internal retries.
Ordinary launches retain `REPO_BRANCH` for checkout but omit the base constraint. Command failures
and malformed typed provider/ref output fail loudly; valid nonmatching state remains close-pending.
The epic layer does not repeat those probes, parse transcripts, call a provider, push, merge, or
check out another branch.
`Process.ExitCode` after `WaitForExit` is the production authority. The persisted/replay exit domain
is limited to 0..255 because POSIX exposes only that portable range. Legacy `exit:0` records remain
merge-success checkpoints equivalent to `awaiting-merge`.
An injected out-of-domain result follows the launch-error path, attempts the same CAS to
`invocation-failed`, and returns a structured failure receipt; zero is never substituted.
A start exception does the same. A terminal-write failure still throws, including after launcher exit
zero. The run GUID deterministically names its container. Existing `running` state probes only that
container: an active container refuses a second launch, an absent/exited container CAS-reconciles the
same run to `invocation-failed` and replays that terminal receipt without relaunch, and probe uncertainty
fails without changing bytes. Existing non-success terminal state is replayed without selecting a
sibling.

Only `awaiting-merge` and legacy `exit:0` may advance. An unchanged target remains at the merge stop.
For a changed target, the loop uses `git merge-base --is-ancestor` to prove the new commit moves
forward. Before any state mutation, the rollup parser requires unique canonical child ids, consistent
boolean child states, exact derived nonnegative counts and completion, and `NextChild` equal to the
first received incomplete, unblocked child (including its folder when present in `Children`). It then
requires the prior child to occur exactly once, be complete, and no longer be `NextChild`. Any invalid
or contradictory graph or non-forward target leaves the six-field record byte-identical and launches
nothing. When another child is eligible, one CAS replaces the prior checkpoint directly with a fresh
`selected` record for the new target/child/run; normal `selected` restart and `selected` → `running`
launch semantics then apply. A replacement race fails without overwriting the winner.

When the refreshed rollup is complete, a generation-checked delete clears the checkpoint and returns
an explicit clean completion with no launch. When the rollup is incomplete but has no `NextChild`, the
loop returns an explicit blocked stop (wrapper exit 42) and deliberately retains the prior success
checkpoint. That checkpoint is the retry anchor: a later invocation can re-evaluate the same merge
against a repaired dependency graph without a seventh persisted field or a second state family. A
delete race likewise fails without deleting the competing state. Target refresh is read-only: the epic
layer never fetches, pulls, checks out, merges, pushes, or invokes a provider API.

## Modes

### Host Mode

- Creates a git worktree at `<repo>.worktrees/feature-<slug>`
- Runs `copilot` CLI per phase (one invocation = one context window)
- Uses `System.Diagnostics.Process` with `RedirectStandardOutput` + `OutputDataReceived` for live streaming
- Timeout enforcement via elapsed-time polling + `Kill()`
- Transcripts saved as `--share=<path>` output

### Container Mode

- Builds image from `.github/skills/autopilot/devcontainer/Dockerfile`
- Passes auth via env file (prepared by `prepare-env-file.ps1`)
- Container entry point: `container-entrypoint.sh` handles clone, branch, and targets selected by
  the deterministic `plan-dispatch.sh` helper
- Sourcing `container-entrypoint.sh` exposes only its pure phase-state and recovery probes; bootstrap
  remains executable-only. Target selection and completion handoff policy stay in `plan-dispatch.sh`.
- Phase selection follows the one-phase autonomy contract in
  [plan-workflow.design.md](plan-workflow.design.md); container resume additionally requires the
  phase's canonically validated durable harvest receipt before skipping checked work. The validator
  and its module closure are copied into the image as root-owned read-only files, so a cloned branch
  cannot replace the pre-admission trust boundary.
- Nonzero and false-success phase exits stage recoverable tracked/untracked paths individually,
  commit and push them fail-loud, then preserve the original phase status; preservation failure exits
  `70` for container recovery instead of claiming the work is durable
- Zero-exit targets are not terminal until committed phase-close proof is valid. The entrypoint uses
  bounded same-session handoffs for pending completion and publishes the work branch before every
  close probe. Finalization additionally requires terminal phase gates, an exact committed archive
  transition, local/remote work-branch OID equality, and one typed open PR matching the work
  branch's name and OID. Epic initial launches and trusted internal retries use
  `EXPECTED_START_COMMIT` to bind `REPO_BRANCH` as the exact PR base; a missing epic target is an
  input error. Ordinary launches still use `REPO_BRANCH` for checkout but pass no PR-base constraint.
- Timeout uses the native `docker run` process wait handle; `docker stop`/`docker kill` run only after
  the whole-run deadline
- Transcripts extracted via `docker cp`; containers are removed after normal outcomes and retained
  with recovery commands when exit `70` says publication durability could not be established

#### Linux container toolchain

The approved toolchain baseline, its acquisition and pinning rules, the provenance and
attestation contract, and the gate's outcome table live in
`docs/design-notes/architecture/autopilot-container-toolchain.design.md`; the structural test
reads that note, so it must stay outside the plan folder that gets archived.

`plugins/autopilot/devcontainer/toolchain.tsv` is the sole additional-tool inventory; its
installed dogfood copy is built through the plugin manifest. The baseline covers search and
navigation, archive/file operations, native builds, Python helpers, shell linting, process and
network diagnostics, SSH, and SQLite. Bootstrap dependencies needed to install and launch
Copilot (`git`, `curl`, `jq`, certificates, GnuPG, Node.js, and npm) remain a separate named
Dockerfile set and are excluded from baseline equality.

The first apt layer accepts enabled sources only from `deb.debian.org` and
`security.debian.org`, installs without recommends, and records OS, source, requested-package,
selected-origin, and installed dependency-closure provenance before cleanup. The image uses the
floating `debian:trixie-slim` base and installs the maintained .NET 10 SDK from Microsoft's
Debian 13 repository after the Debian-only baseline layer. Debian package versions and the
launch-time Copilot version remain floating: one comparison run shares resolved inputs, but
rebuilds on different dates are not promised to be byte-identical.

Every root-trusted fetch that is not an apt package is pinned to a digest or a key fingerprint —
Microsoft's `packages-microsoft-prod.deb` and the GitHub CLI `.deb` by SHA-256, the Docker apt
signing key by full fingerprint — and `curl` runs with `-f` so an error page can never be
installed as a package. A rotated upstream file fails the build closed rather than installing an
unverified one; that maintenance cost is the point. The provenance the smoke script reports is
captured in a **final** root layer, after the last root-owned install, so a layer added below the
recorded one cannot escape the record. Sources are parsed directive-aware (`deb`/`deb-src` lines
and `URIs:` fields, comments skipped) because Debian's own `.sources` file carries a
`snapshot.debian.org` URL inside a comment that a naive URL scan would report as an enabled
origin.

The toolchain is Linux-container-only; Windows Sandbox has a separate cache and lifecycle.
Editors, browsers, language-version managers, cloud CLIs, database servers, and background
daemons are excluded. Root-owned `fd` and `bat` aliases normalize Debian command names, while
`container-toolchain-smoke.sh` runs every manifest case as `autopilot` and emits one bounded
closed-schema JSON line naming each failing case. Image growth is reported against an advisory
250 MiB threshold rather than failing solely on size.

`launch-container.ps1` builds with the installed autopilot skill directory as its context.
`dockerfileExtensions` are inserted at the literal `# Non-root user` anchor, before
`USER autopilot`; keep that anchor stable and keep all root-owned toolchain setup above it.

`Invoke-ContainerToolchainGate.ps1` is the shared Docker-free detector and Docker-backed
measurement runner for local use and CI. It owns the image-input path set, deriving plugin
source/destination pairs from `plugin.json` and local `COPY` sources from the Dockerfile;
context-level and Dockerfile-specific ignore paths are always relevant and must join parity
when present.
Detection consumes NUL-delimited Git output and compares paths ordinally; any unusable base
forces relevance and a closed candidate-only reason. Candidate payload parity, build, smoke,
and bounded output are blocking. Comparable base failure or timeout becomes candidate-only
evidence, while growth above 250 MiB stays advisory. Every invocation writes a bounded
`skalary/container-toolchain-receipt@1` terminal receipt from `finally`; process budgets kill
the process tree and reserve the outer job's upload window.

The smoke JSON is written **by the image being judged**, so on its own it is a claim, not
evidence. The runner therefore attests the claim from the host: it creates a container with
`--network none`, copies the recorded provenance files out with `docker cp`, and hashes and
parses them outside the image. No mount, no volume, no host path is handed to candidate code,
and the container is removed in a `finally`. Attested apt origins are checked against a
four-host allowlist, and disagreement between what the image claimed and what the host read is
itself a failure — an image that reports a clean smoke while its provenance says otherwise is
exactly the case a self-report cannot catch.

Process capture is head+tail bounded (16 KiB head, the remainder as tail, with an explicit
`...[N characters truncated]...` marker), and a failing build or smoke also writes its bounded
capture to a diagnostics log the workflow uploads. A truncated middle is stated rather than
implied, and the exit code of a still-running process is never read.

The workflow carries the detector's candidate-only reason and its relevance verdict into
measurement. A later successful base-checkout retry cannot turn an unusable detection base into
a comparable run, and a measurement-time re-detection that contradicts the detector's `true`
resolves toward the blocking path rather than silently skipping the work the truth table still
expects.

### Sandbox Mode

Windows Sandbox provides isolation with full Win32 support (including WPF/desktop apps that can't build in Linux containers).

**Architecture:**
- Repo mounted **read-only** at `C:\repo` → cloned locally to `C:\work` for isolation
- Toolchain cache at `%LOCALAPPDATA%\autopilot-sandbox-cache` — pre-extracted, mounted read-only
- Session directory (writable) at `C:\sandbox-session` — receives log, transcripts
- Host Git installation mounted at `C:\git` (read-only)

**Toolchain cache (version-keyed, auto-invalidates on bump):**
- `nodejs-<ver>/` — extracted from zip
- `dotnet-<channel>/` — installed via `dotnet-install.ps1`
- `gh-<ver>/` — extracted from zip (not MSI — MSI hangs on read-only mount)
- `powershell-<ver>/` — extracted from zip for the canonical phase validators

**Bootstrap flow (inside sandbox):**
1. Wait for `C:\sandbox-session` mount availability
2. Set PATH: `C:\git\cmd` + `C:\pwsh` + `C:\dotnet` + `C:\nodejs` + `C:\npm-global` + `C:\gh\bin`
3. Install Copilot CLI via npm to writable `C:\npm-global` prefix
4. Read token from session dir, configure `GH_TOKEN` + `gh auth setup-git`
5. `git clone C:\repo C:\work` (fast local clone from read-only mount)
6. `git remote set-url origin <https-url>` (SSH→HTTPS conversion for push)
7. Branch checkout (existing) or creation (new)
8. Per-phase Copilot CLI invocation loop
9. Final `git push`; plan finalization owns PR creation

**Key design decisions:**
- SSH remote converted to HTTPS (`git@github.com:` → `https://github.com/`) because sandbox has no SSH keys; `gh auth setup-git` provides HTTPS credentials
- `safe.directory '*'` — sandbox user differs from file owner on mounted volumes
- Full checkout (no `--no-checkout`) — branch operations need a populated working tree
- Sandbox window visible (`cmd /c start "" /max powershell -NoExit`) for debugging
- Token file written with restrictive ACL, deleted after read inside bootstrap

**Cleanup:** `clean-sandbox-cache.ps1` removes the toolchain cache (~700MB).

## Auth Setup

### GitHub PAT (recommended for Copilot CLI)

Classic PATs (`ghp_*`) are **not supported** by Copilot CLI — a fine-grained PAT is required.

1. Create a fine-grained PAT at github.com/settings/tokens?type=beta with repository permissions:
   - **Contents**: Read and write
   - **Pull requests**: Read and write
   - **Copilot Requests**: Read (enables Copilot API access)
2. Store in Windows Credential Manager:
   ```powershell
   Install-Module CredentialManager -Scope CurrentUser
   New-StoredCredential -Target "copilot-autopilot" -UserName "autopilot" -Password "<PAT>" -Type Generic -Persist LocalMachine
   ```
3. Verify: `Get-StoredCredential -Target "copilot-autopilot"` returns the credential.

### GitHub OAuth (alternative)

1. Run `copilot login` to authenticate via browser
2. Token stored by Copilot CLI in its config directory
3. Store in Credential Manager:
   ```powershell
   New-StoredCredential -Target "copilot-cli" -UserName "oauth" -Password "<token>" -Persist LocalMachine
   ```

### Azure DevOps (for ADO-hosted repos)

1. Run `az login --use-device-code` to authenticate
2. Token fetched at runtime via `az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798`
3. Verify: `az account show` returns correct subscription
4. Set `gitProvider: "ado"`, `gitAuth: "azure-cli"` in `.autopilot.json`

## Configuration (`.autopilot.json`)

Per-repo, gitignored, never committed — the plugin ships `.autopilot.json.example` only. The in-editor first-run bootstrap (autopilot skill) writes it; headless `launch.ps1` fails loud if it is missing.

```json
{
  "runtime": "container",
  "copilotAuth": "pat",
  "gitProvider": "github",
  "gitAuth": "pat-shared",
   "model": "gpt-5.6-sol",
   "context": "long_context",
   "reasoningEffort": "high",
  "git": { "name": "autopilot", "email": "autopilot@users.noreply.github.com" },
  "timeout": 60,
  "maxIterationsPerStep": 5,
  "build": "npm run build",
  "test": "npm test"
}
```

Key fields:
- `runtime`: `host`, `container`, or `sandbox` (all three implemented)
- `copilotAuth`: `pat` or `oauth` (string enum) — selects how the CLI authenticates
- `gitProvider`: `github` or `ado`
- `gitAuth`: `pat-shared`, `oauth`, or `azure-cli`
- `model`: Bare Copilot CLI model slug; the shipped default is `gpt-5.6-sol`
- `context`: Copilot CLI context tier (`default` or `long_context`)
- `reasoningEffort`: Copilot CLI reasoning depth (`low`, `medium`, `high`, `xhigh`, or `max`)
- `build`/`test`: Coarse-filtered by schema prefix pattern; authoritative argv tokenization + flag denylist enforced in `launch.ps1`.
- `timeout`: Minutes per phase before force-kill; bounded same-session completion handoffs share one target budget. Host mode enforces it around each Copilot CLI invocation; container mode enforces it inside the entrypoint, which is the only place target boundaries are visible.
- `planTimeout`: Optional whole-run cap in minutes across all phases (container mode; default 1440). Must be `>= timeout`. On expiry the host sends `docker stop --time 30` and the entrypoint commits + pushes in-flight work before exiting `143`.
- `maxIterationsPerStep`: Build/test/acceptance fix-retry cap. Code-review retries are governed separately by the durable three-cycle phase/finalization gates.
- `offlinePackages` (optional): offline package bundling for container/sandbox. Object with boolean `enabled`; optional `ecosystems` array (`dotnet`/`npm`); optional `maxRebundles` integer ≥ 1 (default 3). Absent → disabled. See **Offline Package Bundling** below.

**No plan path in config.** `launch.ps1` takes `-PlanSlug` and derives `docs/implementation-plans/<PlanSlug>/plan.md`; the config never carries a plan path.

Schema: `plugins/autopilot/schemas/autopilot.schema.json`

## Custom Host Launch Command

Host mode may run a custom Copilot CLI executable (e.g. a corporate wrapper injecting MCP servers + internal skills) instead of vanilla `copilot`. Configured via operator-provisioned, gitignored `.autopilot.host.json` at the repo root (schema: `plugins/autopilot/schemas/autopilot.host.schema.json`, draft 2020-12). `launch-host.ps1` is the **sole reader** — the skill and agent never touch the file (agent Absolute Rule #10).

`Resolve-HostCommand` (in `host-command.ps1`, dot-sourced by `launch-host.ps1` only) reads the file **once** before the phase loop, resolves `command` to an absolute path, classifies type (`exe`/`bat`/`cmd`/`ps1` by extension), and returns `@{ Path; Type; ExtraArgs }`. `Invoke-CopilotPhase` branches per type — direct-`.exe` via `ProcessStartInfo.ArgumentList` (no shell), `.bat`/`.cmd`→`cmd.exe /c` and `.ps1`→`powershell.exe -File` via denylist-backed per-token quoting.

> **Security — headless, no approval prompt.** `launch-host.ps1` runs the Copilot CLI via `System.Diagnostics.Process` (`UseShellExecute=$false`) with **no VS Code command-approval popup**. `command` therefore runs unattended. Point it only at trusted binaries. Defense in depth: absent config → `copilot` (type classified by the resolved shim's extension, npm shims are `*.cmd`); present-but-invalid (malformed JSON, empty `command`, shell metachar in `command`/`args`) → throw before any phase starts (never silent-fallback); gitignore keeps the file host-local. Residual local-persistence risk (untrusted build/test planting the file) is accepted and documented (RISK-5).

**Disable toggle.** `AUTOPILOT_DISABLE_HOST=true` makes the skill omit Host from its menu **and** makes `launch.ps1` refuse `-Runtime host` and exit non-zero.

## Offline Package Bundling

Sealed runtimes (container/sandbox) may have no network access to package registries. When `.autopilot.json` `offlinePackages.enabled` is true and the runtime is container/sandbox, the host pre-builds a package feed and the runtime restores from it offline. Host mode ignores `offlinePackages` (warn-and-ignore).

**Feed build (host).** `prepare-packages.ps1` (dot-sourceable) restores NuGet and/or npm packages into a per-branch feed laid out as `<FeedRoot>/<repo-leaf>/<branch>/{nuget,npm}`. `launch.ps1` builds the feed before dispatch and passes `-FeedPath` to the runtime orchestrator.

**Read-only mount + writable copy.** The orchestrators mount the feed read-only (container: `-v <feed>:/feed:ro`; sandbox: a read-only `C:\feed` MappedFolder) and set `AUTOPILOT_OFFLINE=true` + `AUTOPILOT_FEED`. The bootstrap copies the feed into a writable cache (`$HOME/.autopilot-cache`), emits a `nuget.config` with `<clear/>` + a `globalPackagesFolder`, and points npm at the cache via `npm_config_cache`/`npm_config_offline`. The read-only source is never mutated.

**Rebundle round-trip (exit 43).** If a step needs a package missing from the feed, the agent commits the **manifest only** (never the lockfile), pushes the work branch, and exits `43`. The host owns the loop: `Invoke-AutopilotDispatch` (in `autopilot-dispatch.ps1`) calls `prepare-packages.ps1 -Branch <work-branch>` (which regenerates + commits + pushes the lockfile), then relaunches the same runtime — the re-prep completes before the relaunch clones. Capped by `maxRebundles` (default 3); on cap it warns and surfaces exit 43. This is distinct from the `42` @human stop.

**Out-of-tree offline config.** The runtime never commits `nuget.config` or npm config into the repo; offline wiring lives in the writable cache / environment only. The repo carries the manifest (and host-regenerated lockfile) but no offline machinery.

## First-run Config Bootstrap

The in-editor autopilot skill — not the launcher — owns first-run config. On Autonomous selection it checks for repo-root `.autopilot.json`; if absent it interviews the user, writes the file from `.autopilot.json.example`, and structurally validates required fields/types before invoking `launch.ps1`. See [autopilot-skill.design.md](autopilot-skill.design.md).

## Agent Definition (`.github/agents/autopilot.agent.md`)

Custom agent loaded by Copilot CLI. Implements the single-phase execution loop:
1. Read plan → require shared planning context `confirmed` for enrolled plans → find next `[ ]` step → mark `[~]`
2. Implement → focused build/test of the affected surface → format
3. `git add <specific-files>` → commit (atomic with plan mark)
4. Loop until phase complete → primary-only `/cr post-phase` review → push
5. After all phases → primary + secondary `/cr plan-finalization` review over the whole branch

The affected surface includes changed behavior plus direct consumers, generated artifacts, and architecture contracts that the edit can invalidate. Step loops run named evidence and focused targets only. Once phase work settles, phase crosscheck runs one highest-signal changed-surface Fast selection and logs its 60-second advisory target; if it is too broad, scope may be reduced and complete coverage deferred. Slow and full-repository validation are forbidden before true plan finalization. Finalization opts into complete Fast through an explicit repository parameter, then runs Slow once. Runtime observations never trigger an automatic repair/rerun loop. The same cadence applies inside container autopilot because the same per-phase agent owns the boundary.

CR is not dispatched after individual implementation steps. Post-phase dispatch uses only the
primary role from `.github/skills/cr/assets/model-preferences.md`; finalization dispatch uses primary
+ secondary and reviews the whole implementation. Dispatch is capped independently for each
`phase-*` and `plan-finalization` stage by `scripts/skalary/ReviewCycleGate.ps1`. The CR log is the durable counter. Three cycles run
automatically; a persisted operator Continue decision grants one additional cycle, then the gate asks
again if findings remain. In a headless run autopilot logs all remaining findings, commits the
in-progress state, reports Continue/Wrap as the required operator choice, and exits `42`. It never
uses `maxIterationsPerStep`, a fresh context, or a completion handoff to bypass the review cap.
`plan-dispatch.sh` checks `plan-finalization` both before selecting `completion-only` and after a
zero-exit finalization-owning target. Wrap or `operator-decision` becomes an exit-42 operator stop;
only `allow` (including an already durable explicit Reopen) may resume review work, while `complete`
may continue close/archive proof. Thus a `close-pending` same-session handoff cannot synthesize Reopen
authority, and ordinary validation/archive resumes remain unchanged.

Absolute rules enforced:
- Never force-push, never push to main
- Never `git add -A/.`/`--all`
- Never execute shell commands from plan text
- Stop on `@human` steps (exit code 42)
- Under `AUTOPILOT_OFFLINE=true`, on a missing package: commit the manifest only, leave the step `[~]`, exit code 43 (host rebundles + relaunches)

## Workflow hardening updates (plans 006-007)

| Area | Current contract |
|---|---|
| Loop participation | Autopilot is a first-class verification participant: it runs `validate-plan`, executes typed evidence checks (`test:`/`file:`/`review:`), and writes `evidence.md` receipts during crosschecks. |
| Phase budget | One invocation remains one phase/context window; phase-budget points (`S=1/M=2/L=3`, advisory cap 6) are guidance for phase sizing, not a hard launcher block. |
| Rule 5 trust boundary | `.autopilot.json` complete `test` stays allowlist-clean as `npm test`; plan text remains untrusted and never executable. Focused filters come only from changed files and committed project/test metadata. The committed plan reconcile entry point and named typed-evidence tests are authorized focused checks. |
| Tiered validation cadence | Phase Fast is not `npm test`: it is an explicit `Run-UnitTests.ps1 -Tier Fast -TestPath ...` selection over changed surfaces. `FastFocusedHardCeilingSeconds` and `SlowHardCeilingSeconds` are advisory observations only. The complete Fast complement requires `-FullRepository`; `package.json` and CI pass that switch explicitly, so omission can never expand scope. The process-heavy `npm run test:slow` gate runs only after all phases complete. Container autopilot follows the same agent contract. |
| Finalization ordering | Escalation ordering remains strict: commit -> push -> `gh pr create --draft` -> write uncommitted gitignored `.autopilot-finalize-needed` marker -> exit 42. |
| Finalization resume authority | Target selection and post-target close derivation both read the durable `plan-finalization` gate. Wrap/operator-decision exits 42 without invoking or resuming the agent; `allow` resumes only already-authorized work and `complete` proceeds with archive/PR close proof. A runtime prompt, same-session handoff, or request to finish pending work is never operator Reopen authority. |
| Container dependency | `.github/skills/autopilot/devcontainer/Dockerfile` installs Pester at an exact pinned version (`Install-PSResource -Name Pester -Version "[5.6.1]"`) so `test:unit` and `test:` evidence are runnable in container-autopilot. |
| Canonical harvest host | Workflow-memory harvest is specified in `autopilot.agent.md` (canonical), not `ci` assets; `/ci` guidance is a marked mirror. |
| Harvest guardrail | Finalization harvest runs when the installed `.github/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1` exists. Ledger categories scaffold on demand, so fresh installs do not require preexisting ledger files. Missing infra falls through to standard branch behavior. |
| Harvest branch split | Append-harvest executes and commits before branch selection; autonomous branch archives + real PR, escalation branch runs `/udn` + prune + draft PR + marker + exit 42 (never archive). |
| Script invocation safety | Installed `Invoke-PhaseHarvest.ps1`, autopilot-owned `Invoke-SiDueEnqueue.ps1`, `Remove-LedgerEntry.ps1`, `Update-FeedbackQueue.ps1`, and dependency-installed `Enqueue-SiDue.ps1` are the Rule-5 carve-out and must be invoked with argument arrays, never shell-interpolated command strings. |
| Durable writer closure | Root-canonical capture/ledger writers import `AtomicStore.psm1`; `Invoke-PhaseHarvest.ps1` imports the shared `LedgerStore.psm1` scalar/batch engine. Autopilot carries both generated modules plus `PlanState.psm1` under `.github/skills/autopilot/scripts/`, so installed phase harvest uses the same confinement, lock/CAS/status, bounds, and atomic-replace contracts. |
| Planning admission | Before any step/log mutation, autopilot calls shared `Get-PlanningContextState`. Enrolled `pending`, `stale`, `missing`, or `invalid` plans exit `42` for operator confirmation; marker-less legacy plans proceed. |
| Step-role dispatch | After planning admission, environment/worktree setup, active marking, and reconcile, the agent declares Designer + Validator -> Implementor -> Judge through the shared four-task run-scoped fleet. Existing model/tool bindings and the Implementor edit/build/test/format/fix loop stay authoritative; Judge completes before commit. Commit/push, promotion, phase review, harvest, and all host/container/credential boundaries remain outside dispatch. |
| Runtime close failure | The close probe exits `2` when canonical admission, checklist, or receipt state is invalid. Runtime adapters preserve recoverable work and surface terminal exit `3`; this is distinct from the agent's deliberate `42` operator stop and `43` rebundle request. |
| Phase-harvest execution | Phase crosscheck invokes the bound installed autopilot copy with `-Phase`, commits the receipt plus changed ledger categories before phase teardown, and finalization invokes `-FinalSweep`; only `complete`/`empty` permit phase completion or archival. `Get-PhaseExecutionState.ps1` is the shared read-only close probe used by container, host, and sandbox: an incomplete checklist returns `execution-required`, a complete checklist without a receipt returns `close-pending`, a canonically validated receipt returns `closed`, and malformed close state fails. Degraded phases are retried at the phase boundary because final sweep only replays existing receipts; unresolved degradation stops completion. The installed scripts are in autopilot's closed execution carve-out, and both current/legacy receipt trees are declared first-use scaffolds. |
| Ephemeral capture durability | Each phase initializes and commits `cr-log.md`, `learnings.md`, and `capture.md` sections by explicit filename with `No entries for this phase.` placeholders; harvest fails loud only on missing required sections. |
| Headless SI due | Autopilot explicitly depends on `self-improvement` but never runs `/si`. Only after the autonomous archive commit is successfully pushed does its installed `Invoke-SiDueEnqueue.ps1` wrapper invoke dependency-installed `Enqueue-SiDue.ps1` with bound plan/source arguments. The due binds the complete-source OID, duplicate enqueue is a byte-stable no-op, and any retry-visible SI state delta is still committed/pushed before the plan PR. The wrapper converts writer exceptions/non-complete statuses into an explicit `degraded` result, so failure reporting and continuation are executable rather than prompt-only. |
| Distribution proof | `test:LearningLoop.PayloadOwnershipAndDrift` proves the dependency, installed invocation/carve-out, root-canonical phase-harvest bundle closure, receipt scaffolds, dogfood bytes, versions, marketplace, and registry as one contract. This remains part of the existing unit suite rather than a new validation gate. |

### Model field format

The agent's `model:` frontmatter uses a **bare Copilot CLI model slug** (e.g. `gpt-5.6-sol`), not the qualified `Model Name (vendor)` form used by VS Code-hosted agents. Copilot CLI resolves the plain slug; the parenthesized-vendor format is a VS Code convention and does not apply here. Keep the two formats distinct — the dr/cr review subagents run in VS Code and use `Model Name (copilot)`, while this agent runs under Copilot CLI and uses the bare slug. Launchers also pass `--context` and `--effort` explicitly so persisted user settings cannot override the project configuration.

## Script Inventory

| Script | Purpose |
|--------|---------|
| `EpicAutopilot.psm1` | Host-only epic child admission/state machine; refreshes and CAS-advances only merge-proven success, preserves terminal failures and blocked retry anchors, exports only the three-argument production host loop, and keeps test adapters private |
| `Invoke-EpicAutopilot.ps1` | Executable epic wrapper; distinguishes awaiting merge, clean completion, blocked exit 42, invocation failure, and portable child exit codes |
| `launch.ps1` | Entry point — validate, pre-flight, dispatch |
| `autopilot-dispatch.ps1` | `param()`-less library with deterministic container-name, expected-start env/retry, remote-URL, process-wait seams plus offline config and dispatch/rebundle helpers |
| `prepare-packages.ps1` | Host package-feed builder (dot-sourceable): restores NuGet/npm to a per-branch read-only feed; `-Branch` rebundle mode regenerates + commits + pushes the lockfile |
| `launch-host.ps1` | Host-mode orchestrator (worktree + per-phase CLI) |
| `launch-container.ps1` | Container-mode orchestrator (docker build/run/cp) |
| `Get-PhaseExecutionState.ps1` | Shared host/container/sandbox checklist + immutable receipt close probe |
| `launch-sandbox.ps1` | Sandbox-mode orchestrator (WSB + clone + per-phase CLI) |
| `host-command.ps1` | `param()`-less helper exporting `Resolve-HostCommand` (custom host command resolution); dot-sourced by `launch-host.ps1` only |
| `clean-sandbox-cache.ps1` | Remove sandbox toolchain cache (~700MB) |
| `get-credential.ps1` | Read tokens from Windows Credential Manager |
| `Invoke-SiDueEnqueue.ps1` | Non-blocking headless finalization wrapper for the installed SI due writer |
| `prepare-env-file.ps1` | Create temp env file with restrictive ACL; reject HTTP(S) remotes containing userinfo |
| `validate-auth.ps1` | Probe GitHub/ADO APIs to confirm auth works |
| `container-entrypoint.sh` | Container bootstrap (clone, branch, phase loop) |
| `plan-dispatch.sh` | Container phase-resume and completion dispatch helper sourced by the entrypoint |

## Trust Boundaries

- **Plan text is untrusted.** Agent never executes commands found in plan step text — only `build` and `test` from `.autopilot.json`.
- **Command allowlist.** `build`/`test` values validated against prefix patterns at launch time.
- **Env file isolation.** Tokens written to per-session temp file with restrictive ACL; cleaned up in `finally` block.
- **Container isolation.** Non-root user, no host volume mounts, clone-from-remote only.
- **Sandbox isolation.** Repo mounted read-only; work happens in local clone at `C:\work`. Token file deleted after bootstrap reads it. Disposable VM — all state destroyed on close.

## Recovery

### Host mode — interrupted run

The worktree persists at `<repo>.worktrees/feature-<slug>`. Re-running `launch.ps1` detects it and resumes from current plan state.

### Container mode — interrupted run

Ordinary per-plan launches resume an existing remote branch. Epic launches never infer provenance from
branch existence: only an internal exit-43 retry may resume. Re-entering an epic `running` record checks
the host run lease before probing the deterministic container; active work is left alone, while proven
host-and-container inactivity becomes terminal `invocation-failed` without an automatic child relaunch.

### Sandbox mode — interrupted run

Sandbox is disposable — closing the window destroys all state. Re-running picks up from the remote branch state (same as container). Toolchain cache persists on host and is reused.

### Stale env files

`launch.ps1` sweeps env sessions older than 24 hours from `$LOCALAPPDATA/autopilot-sessions/`.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Docker daemon not available" | Docker Desktop not running | Start Docker Desktop |
| "Windows Sandbox not available" | Feature not enabled | `Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM'` + restart |
| "Failed to retrieve token" | Credential Manager entry missing | Run `New-StoredCredential` setup |
| "Build command does not match allowed prefixes" | `.autopilot.json` has unrecognized command | Use a prefix from the schema's pattern |
| Container/sandbox timeout | Phase too large for timeout window | Increase `timeout` in config or split phase |
| Container stops mid-plan, exit 143 | Whole-run cap (`planTimeout`) reached | Raise `planTimeout`; work up to the last step is already pushed |
| Container stops mid-plan, exit 124 | A single phase exceeded `timeout` | Raise `timeout` or split the phase; the truncated phase is pushed, later phases are not started |
| "Auth validation failed" | Token expired or insufficient scope | Regenerate PAT / re-run `az login` |
| "Host key verification failed" (sandbox) | Remote URL uses SSH | SSH→HTTPS auto-conversion handles this |
| "Plan not found" (sandbox) | Clone used `--no-checkout` | Full checkout is used — verify clone step |

## Limitations

- **Windows-only orchestrator** — scripts use PowerShell + Windows Credential Manager
- **Some app types can't build in Linux containers** — e.g. WPF/desktop apps require host or sandbox mode
- **Sandbox requires Windows Pro/Enterprise** — `Containers-DisposableClientVM` feature
- **Docker Desktop required** for container mode
- **Copilot CLI license required** for the authenticated user
- **One phase per context window** — prevents context exhaustion but adds invocation overhead
- **Sandbox is host-polled** — the launcher enforces the configured timeout, terminates the process tree, and preserves terminal status for recovery.
