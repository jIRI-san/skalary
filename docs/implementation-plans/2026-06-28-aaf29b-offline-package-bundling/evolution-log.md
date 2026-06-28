# Evolution Log — offline-package-bundling

## DR Round 1 (dr-opus, dr-codex; dr-gemini returned no output)

### Issues found
- **Critical** — npm cacache + NuGet global-packages folder are not writable; pointing restore directly at the read-only mount fails `EROFS` on *present* packages, never reaching the rebundle path (opus F1).
- **Critical** — NuGet feed-layout conflation: `restore --packages` produces a global-packages folder, but the plan generated a `nuget.config` folder **source** (expects `.nupkg` files) — dotnet offline restore would not resolve (opus F3, codex F3).
- **Critical** — Sandbox rebundle loop unimplementable: `launch-sandbox.ps1` is fire-and-forget (`Start-Process`, no wait); cannot return exit 43; the mocked RebundleLoop test would go green while the real sandbox path is dead (opus F2, codex F4).
- **Critical/High** — Agent commit contract: agent only commits after build/test pass; rebundle needs the failing-restore manifest committed first. Push owner contradictory (Decisions: agent pushes; step 3.2: entrypoint pushes) (codex F1, opus F6/F9).
- **High** — `prefer-offline=true` falls back to the network on a cache miss → defeats isolation and silently skips the rebundle trigger for public transitives; must use `offline=true` + cleared NuGet sources (opus F4, codex F2).
- **High** — Generated `nuget.config`/`.npmrc` written into the work tree clobber a repo's *tracked* configs and can be staged by the agent; `.git/info/exclude` has no effect on tracked files (opus F5).
- **High** — dotnet restore under-specified: no lockfile/`--locked-mode`, fallback folders/`RestoreSources`/workload packs not disabled, writable global-packages folder undefined (codex F3).
- **Medium** — `prepare-env-file.ps1` (the real env-file owner) not an edit target, so `AUTOPILOT_OFFLINE` never reaches the entrypoint (opus F7).
- **Medium** — `launch.ps1` reads `offlinePackages.*` under `Set-StrictMode` with no guard/defaulting → throws when absent; "default off" broken (opus F8, codex F5).
- **Medium** — Plan-mark state across rebundle unspecified (`[~]` resume contract) (opus F9).
- **Medium** — REQ-7/REQ-8 verified only by `#contains` keyword presence → can't confirm sequencing semantics; add `review:cr` (opus F10).
- **Medium** — Shared per-repo feed races with a live sandbox / concurrent runs; scope per branch + add risk (opus F11).
- **Medium** — Missing `[after:]` deps: 2.2 after 2.1; 5.2 after 2.2/3.2/4.3/5.1 (codex F6).
- **Medium** — Branch naming/fetch semantics vague; unify `$WorkBranch = feature/$PlanSlug`, validate remote ref (codex F7).
- **Medium** — RebundleLoop test needs a testable function boundary (launch.ps1 calls `exit`); extract dispatch into a function returning int (codex F8).
- **Low** — Phase 5 cohesion weak (5.4 docs share no state); split docs out (opus F12).
- **Low** — Agent exit-43 (5.1) and runtime catch-43 (3.2/4.2) are a contract pair across phases with no deps (opus F13).

### Issues fixed (all auto-applied — clear-cut technical corrections, none contradict user decisions)
- Feed model made consistent: dotnet global-packages folder + npm cache, **copied at runtime** from the read-only mount to a writable cache; restore uses `globalPackagesFolder`/`cache` = the writable copy (fixes F1, F3).
- Offline **enforced**: npm `offline=true`, NuGet `<clear/>` sources + disabled fallback folders, locked restores (`npm ci`, `--locked-mode`), committed-lockfile requirement (fixes F4, codex F3, RISK-3).
- Offline config moved **out-of-tree** (`--configfile`/`NUGET_CONFIG`, `--userconfig`/`npm_config_*`); nothing written to the work clone (fixes F5, RISK-6).
- Single rebundle signal + one owner: agent stages manifests+lockfiles, leaves step `[~]`, commits, `exit 43` (no push/marker); runtime adapter pushes + signals (fixes F6/F9, codex F1).
- Sandbox launcher made **blocking** via a bootstrap-written completion sentinel poll + stale-marker clear + timeout (fixes F2/F4).
- `prepare-env-file.ps1` added as an edit target (fixes F7).
- `launch.ps1` StrictMode-safe access + defaulting; dispatch extracted into a testable function; RebundleLoop test retargeted (fixes F8/codex F5/F8).
- `review:cr` added to REQ-7/REQ-8/REQ-9 (fixes F10).
- Feed scoped per repo-leaf+branch; new RISK-7 (fixes F11).
- Deps tightened: 2.2 `[after:2.1]`, 5.1 `[after:3.2,4.2]`, 5.2 `[after:2.2,3.1,4.1,5.1]` (fixes F6/F13).
- Branch naming unified to `$WorkBranch`, remote-ref validation in 2.2 (fixes F7).
- Phase 5 docs split into Phase 7; Phase 5 now 7pt (fixes F12).

### Issues deferred
- None. All findings applied.

## DR Round 2 (self-conducted; dr-* subagents not invokable in this context)

Round 2 re-read `container-entrypoint.sh` and the revised plan against the round-1 decisions (read in evolution log to avoid re-litigating fixed issues).

### Issues found
- **Critical** — The offline agent **cannot produce a valid lockfile**. Adding a package edits a manifest, but regenerating `package-lock.json` / `packages.lock.json` requires resolving the new package (network the agent lacks). The round-1 plan had the agent stage "manifests + lockfiles"; a stale lock + edited manifest makes the relaunched container's `npm ci` / `--locked-mode` hard-fail forever — the loop never converges (R2-C1).
- **Medium** — Sandbox sentinel: 4.2 wrote the completion sentinel "at the end," so a bootstrap crash *before* the end never releases the host poll → guaranteed timeout every failure (R2-M1).
- **Low** — NuGet source-clearing completeness not pinned: `--configfile` *replaces* (not merges) machine/user config discovery; `RestoreAdditionalProjectSources` is repo-controlled and out of scope (R2-L1).

### Confirmed sound (no change)
- Exit-43 propagation through `set -euo pipefail`: copilot's nonzero exit is caught by the `|| { }` brace group (runs in-shell, not a subshell), so an `exit 43` there terminates the script before the unconditional end-of-run `git push` (verified against the actual entrypoint).
- `[~]` resume contract: the entrypoint's uncompleted-step grep already matches `[~]`, keeping the rebundle phase active on relaunch.
- Single feed copy after clone (not per-phase); blocking sentinel + timeout; per-branch feed scoping.

### Issues fixed (all auto-applied)
- **Lockfile ownership moved to the host**: agent stages **manifests only** (5.1); `prepare-packages.ps1 -Branch` runs an **unlocked** network restore that regenerates the lockfile, commits it as a follow-up commit, and pushes to `$WorkBranch` **before** relaunch (2.2); initial prep (2.1) and all runtime restores stay **locked** against the committed lock. Updated Decisions (single-signal bullet + new "Host owns lockfile regeneration" bullet), REQ-1, REQ-5, RISK-3, steps 2.1/2.2/2.3/5.1/5.2 (R2-C1).
- Sandbox sentinel moved to a `trap`/`finally` so it always fires even on bootstrap failure (4.2) (R2-M1).
- Tightened 3.2 wording: `--configfile` replaces config discovery; `RestoreAdditionalProjectSources` out of scope (R2-L1).

### Issues deferred
- None. All findings applied.
