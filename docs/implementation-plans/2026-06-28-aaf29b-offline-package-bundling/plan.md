# aaf29b: Offline package bundling for container/sandbox autopilot
<!-- plan-id: aaf29b -->
<!-- cip-stage: reviewed -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: host-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- expected-packages: dotnet:none; npm:none (this plan adds no new third-party packages) -->

## Decisions
<!-- Key decisions made during planning — one bullet per decision -->
- **Local folder feeds (not mirror registries).** Host produces a per-repo/per-branch feed: dotnet via `dotnet restore --packages <feed>/nuget` (a NuGet global-packages folder) and npm via `npm ci` populating `<feed>/npm` (cache). No verdaccio / NuGet server. Both ecosystems require a committed lockfile (`packages.lock.json` / `package-lock.json`); offline-enabled projects without one fail loud in host prep so host and container resolve identically (RISK-3).
- **Read-only mount is a SOURCE; runtime copies to a writable cache.** The feed reaches the container via `-v <feed>:/feed:ro` and the sandbox via a read-only `MappedFolder` at `C:\feed`. Because npm cacache and the NuGet global-packages folder must be writable, the entrypoint/bootstrap copies `/feed` into a writable per-run location and restores from there — the mount itself stays read-only (RISK-1).
- **Offline config is out-of-tree, never written into the work clone.** Restore uses an out-of-tree NuGet config (`--configfile`/`NUGET_CONFIG`) with `<clear/>` package sources + disabled fallback folders + `globalPackagesFolder` = the writable copy, and out-of-tree npm config (`--userconfig`/`npm_config_*` env) with `cache=<writable copy>` + `offline=true`. Nothing is written to `/work` (or `C:\work`), so a repo's own *tracked* `nuget.config`/`.npmrc` is never clobbered and there is nothing to accidentally commit (RISK-6).
- **Offline is enforced, not preferred.** npm uses `offline=true` (not `prefer-offline`) and NuGet clears all online sources + fallback folders, so any cache/feed miss hard-fails into the rebundle path instead of silently fetching from the network. Restores run locked (`--locked-mode` / `npm ci`).
- **Opt-in via `offlinePackages` config.** Absent or `enabled:false` → container/sandbox behave exactly as today. Host mode ignores the field (it has native auth to the private stream). `launch.ps1` reads it StrictMode-safely (absent → disabled; `maxRebundles` defaults to 3; types validated before any prep).
- **Single rebundle signal, one owner per step.** On an offline restore that misses a package, the agent stages only the package **manifests** (`package.json` / `*.csproj`) — **not lockfiles** — leaves the step `[~]`, makes a rebundle-request commit, and `exit 43`. It does **not** push and does **not** write a marker. The runtime adapter owns the rest: the container entrypoint pushes `$WorkBranch` then `exit 43`; the sandbox bootstrap pushes then writes `.autopilot-rebundle-needed` into the writable session dir. Exit 43 is distinct from `@human` exit 42. Resume contract: a committed manifest + `[~]` step ⇒ the relaunched agent continues that step against the rebundled feed + regenerated lock.
- **Host owns lockfile regeneration (the agent can't make one offline).** Adding a package edits a manifest, but regenerating `package-lock.json` / `packages.lock.json` requires resolving the new package — network the offline agent lacks; a stale lock + edited manifest makes `npm ci` / `--locked-mode` hard-fail forever. So `prepare-packages.ps1 -Branch` (host, with private-stream auth) runs an **unlocked** network restore to regenerate the lockfile, commits it as a **follow-up commit**, and pushes to `$WorkBranch` *before* relaunch. The initial host prep (2.1) and every container/sandbox restore run **locked** against that committed lock, so host and runtime resolve identically (RISK-3).
- **`launch.ps1` owns the auto-loop.** When `offlinePackages.enabled` and runtime ∈ {container, sandbox}, it preps the feed, passes `-FeedPath`, and on a rebundle signal re-runs `prepare-packages.ps1 -Branch $WorkBranch` then relaunches, capped by `maxRebundles`, then surfaces to the user. Dispatch is factored into a function returning an integer so the loop is unit-testable without the script's terminal `exit`.
- **Sandbox launch becomes blocking.** `WindowsSandbox.exe` detaches with no exit code, so `launch-sandbox.ps1` clears stale session markers, launches the sandbox, then BLOCKS polling the writable session dir for a bootstrap-written completion sentinel (with a timeout) before reading the rebundle marker (RISK-2).
- **Per-run feed scoping.** The feed dir is keyed by repo-leaf + work branch (not just repo), so concurrent runs and a still-open sandbox holding a read-only mount never collide with a host re-prep (RISK-7).
- **Phase-budget override.** Phases 2 (feed builder, 7pt), 3 (container, 7pt), 5 (agent + launcher loop, 7pt) and 7 (docs + registry + validation, 8pt) exceed the advisory cap 6 — each is a cohesive serial unit (splitting mid-script or mid-release invites half-applied launchers or registries). Override declared here per drafting-guide; the cap is advisory, not a hard block.

## Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Host pre-downloads packages into a per-repo/per-branch local folder feed (dotnet global-packages + npm cache), auto-detecting ecosystems from `*.csproj`/`*.sln` + `package.json` and requiring a committed lockfile; the `-Branch` rebundle path regenerates the lockfile (unlocked network restore) and commits + pushes it. | `test:Autopilot.PreparePackages` (detection, feed layout, idempotency, lockfile-missing fail-loud, `-Branch` lock regen + commit/push) · `file:plugins/autopilot/scripts/prepare-packages.ps1#exists` | 2.1, 2.2, 2.3 |
| REQ-2 | Offline bundling is opt-in via `.autopilot.json` `offlinePackages`; default off preserves current behavior; schema + example + skill bootstrap + StrictMode-safe launcher validation/defaulting. | `file:plugins/autopilot/schemas/autopilot.schema.json#contains:offlinePackages` · `file:plugins/autopilot/.autopilot.json.example#contains:offlinePackages` · `file:plugins/autopilot/skills/autopilot/SKILL.md#contains:offlinePackages` | 1.1, 1.2, 1.4, 5.2 |
| REQ-3 | Container mounts the feed read-only, copies it to a writable cache, and restores fully offline via out-of-tree config; nothing is written to the work tree. | `file:plugins/autopilot/scripts/launch-container.ps1#contains:FeedPath` · `file:plugins/autopilot/scripts/container-entrypoint.sh#contains:AUTOPILOT_OFFLINE` · `test:Autopilot.ContainerOffline` | 3.1, 3.2, 3.3 |
| REQ-4 | Sandbox mounts the feed read-only at `C:\feed`, blocks on a bootstrap completion sentinel, and restores offline via out-of-tree config. | `test:Autopilot.SandboxOffline` (read-only `MappedFolder`, out-of-tree offline config, sentinel poll, session-marker→43) | 4.1, 4.2, 4.3 |
| REQ-5 | On a missing-package offline restore, the agent stages **manifests only** (not lockfiles), leaves the step `[~]`, commits and exits 43; the runtime pushes + signals; the host regenerates+commits the lockfile on re-prep; distinct from `@human` exit 42. | `file:.gitignore#contains:autopilot-rebundle-needed` · `file:plugins/autopilot/agents/autopilot.agent.md#contains:rebundle` · `file:plugins/autopilot/scripts/container-entrypoint.sh#contains:43` | 1.3, 3.2, 4.2, 5.1 |
| REQ-6 | `launch.ps1` auto-loops via a testable dispatch function: on a rebundle signal it re-preps the work branch and relaunches the same mode, capped by `maxRebundles`, then surfaces to the user; host mode skipped. | `test:Autopilot.RebundleLoop` (re-prep + relaunch on code 43, cap, host-mode skip, absent/disabled config no-op) · `file:plugins/autopilot/scripts/launch.ps1#contains:offlinePackages` | 5.2, 5.3 |
| REQ-7 | `/ci` + autopilot skill docs + the autopilot agent explain the offline flow and the exit-43-vs-42 round-trip (host-side loop ownership). | `file:plugins/autopilot/skills/autopilot/SKILL.md#contains:offline` · `file:plugins/continue-implementation/skills/ci/SKILL.md#contains:rebundle` · `review:cr` | 7.1 |
| REQ-8 | `/cip` authoring (interview + template + drafting) makes plans package-aware: capture expected packages, batch package-adding steps to minimize round-trips. | `file:plugins/create-implementation-plan/skills/cip/assets/interview-guide.md#contains:offline` · `file:plugins/create-implementation-plan/skills/cip/assets/plan-template.md#contains:expected-packages` · `file:plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md#contains:rebundle` · `review:cr` | 6.1, 6.2, 6.3 |
| REQ-9 | Design notes, dogfood sync, registry, and plugin versions updated; full test + eval gates pass. | `file:registry.json#contains:prepare-packages` · `file:.github/skills/autopilot/scripts/prepare-packages.ps1#exists` · `file:docs/design-notes/architecture/autopilot-execution.design.md#contains:offline` · `review:cr` | 7.2, 7.3, 7.4, 7.5 |

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Read-only feed mount relaxes the container "no host volume mounts" isolation property. | Medium | Low | Mount is read-only and opt-in; feed holds only host-restored packages; documented in design note + schema description. | 3.1 |
| RISK-2 | Sandbox is interactive/disposable and `WindowsSandbox.exe` detaches — no exit code for the rebundle signal. | High | Medium | Bootstrap always writes a completion sentinel (and `.autopilot-rebundle-needed` on a rebundle) to the writable session dir; `launch-sandbox.ps1` clears stale markers, then BLOCKS polling for the sentinel (with timeout) before returning 43. Documented as best-effort. | 4.1, 4.2, 4.3 |
| RISK-3 | Container/host package resolution diverges, or an offline miss silently fetches from the network, or a rebundle leaves a stale lockfile that can never converge. | Medium | Medium | Require committed lockfiles + locked restore (`npm ci`, `dotnet --locked-mode`); bundle the full cache/global-packages folder; enforce offline (`offline=true`, NuGet `<clear/>` + disabled fallback folders) so any miss fails loud into the rebundle path; the host (not the offline agent) regenerates the lockfile on `-Branch` re-prep and commits+pushes it before relaunch so the committed manifest+lock pair stays consistent. | 2.1, 2.2, 3.2 |
| RISK-4 | Rebundle loop could thrash if a package is genuinely unavailable on the private stream. | Low | Medium | `maxRebundles` cap (default 3); on cap, `launch.ps1` stops and surfaces an actionable error to the user. | 5.2 |
| RISK-5 | `launch-sandbox.ps1` is UTF-16 LE with a literal backtick-dollar here-string — edits risk corruption. | Medium | High | Edit via .NET `ReadAllText`/`WriteAllText` with `UnicodeEncoding($false,$true)`; match the literal `` `$ `` with single-quoted PS strings (per repo memory). Verify non-empty + re-run sandbox structural test after edit. | 4.1 |
| RISK-6 | Generated offline config or the rebundle marker leaks into a commit, or clobbers a repo's tracked `nuget.config`/`.npmrc`. | Medium | Low | Offline config is out-of-tree (never written to the work clone); the agent stages only manifests+lockfiles and never pushes; marker is gitignored; `review:cr` confirms absence. | 3.2, 4.2, 5.1 |
| RISK-7 | Concurrent runs or a live sandbox holding the read-only mount collide with a host feed re-prep. | Medium | Medium | Feed dir scoped per repo-leaf+branch; host re-prep targets the branch feed; the loop relaunches a fresh sandbox rather than re-prepping a feed the VM still holds. | 2.1, 4.1 |

## Phase 1: Config surface
<!-- worktree: feature/aaf29b-offline-package-bundling -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget advisory cap: 6) -->

- [x] 1.1 Add `offlinePackages` object to `autopilot.schema.json` — properties `enabled` (boolean), optional `ecosystems` (array of `dotnet`/`npm`), optional `maxRebundles` (integer ≥1, default 3); NOT added to top-level `required`; describe the read-only-mount + private-stream rationale in the schema `description` (REQ-2, RISK-1) `S`
- [x] 1.2 Add `"offlinePackages": { "enabled": false }` to both `.autopilot.json.example` copies (plugin + dogfood stay byte-identical) (REQ-2) `S`
- [x] 1.3 Add `.autopilot-rebundle-needed` to `.gitignore` under the "Autopilot transient artifacts" block (REQ-5) `S`
- [x] 1.4 Update autopilot `SKILL.md` first-run bootstrap: interview/accept optional `offlinePackages`, structurally validate it when present (object; `enabled` boolean; `ecosystems` array-of-enum; `maxRebundles` number) — mirror the launcher's hand-rolled checks, not JSON-Schema (REQ-2) `M`

## Phase 2: Host feed builder
<!-- worktree: feature/aaf29b-offline-package-bundling -->

- [x] 2.1 Create `plugins/autopilot/scripts/prepare-packages.ps1`: detect ecosystems (`*.csproj`/`*.sln` → dotnet, `package.json` → npm; honor `ecosystems` override), require a committed lockfile per offline-enabled ecosystem (fail loud if missing), restore **locked** (`dotnet restore --packages <feed>/nuget --locked-mode`; `npm ci` into the cache dir) into a per-repo/per-branch feed `$env:LOCALAPPDATA/autopilot-package-feed/<repo-leaf>/<branch>/{nuget,npm}`, idempotent, return the feed path; `Set-StrictMode`, path-confine the repo-leaf + branch keys (REQ-1, RISK-3, RISK-7) `L`
- [x] 2.2 Add `-Branch <work-branch>` rebundle mode to `prepare-packages.ps1`: validate the remote ref exists, `git fetch origin <branch>`, check out the branch into a temp `git worktree` (removed in `finally`); run an **unlocked** network restore (`dotnet restore` / `npm install`) that regenerates the lockfile AND populates the branch-scoped feed; if the lockfile changed, `git add` only the lockfile(s), commit a follow-up `autopilot: rebundle lockfile` commit, and `git push origin <branch>` so the relaunched runtime clones a consistent manifest+lock pair; reuse a single `$WorkBranch` convention (REQ-1, RISK-3) [after: 2.1] `M`
- [x] 2.3 Add `tests/autopilot/PreparePackages.Tests.ps1` (`test:Autopilot.PreparePackages`): ecosystem auto-detect, lockfile-missing fail-loud, feed-dir layout + branch scoping, idempotency, `-Branch` remote-ref validation + lockfile regen → commit/push (mock `git push`), no-op when the lockfile is unchanged, repo-leaf/branch path confinement — mock `dotnet`/`npm`/`git` (REQ-1, REQ-9) [after: 2.1] `M`

## Phase 3: Container offline path
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 `launch-container.ps1` + `prepare-env-file.ps1`: add a `-FeedPath` param to `launch-container.ps1`; when set, append `-v "${FeedPath}:/feed:ro"` to the `docker run` args; inject `AUTOPILOT_OFFLINE=true` + `AUTOPILOT_FEED=/feed` into the env file via `prepare-env-file.ps1` (edit both the plugin script and its dogfood copy); propagate exit code unchanged (43 included) (REQ-3, RISK-1) [after: 1.1] `M`
- [x] 3.2 `container-entrypoint.sh`: when `AUTOPILOT_OFFLINE=true`, after clone copy `/feed` → a writable cache (e.g. `$HOME/.autopilot-cache/{nuget,npm}`) and emit OUT-OF-TREE config — a NuGet config passed via `--configfile`/`NUGET_CONFIG` (which *replaces* machine/user config discovery, no merge) with `<clear/>` sources + disabled fallback folders + `globalPackagesFolder` = the writable copy, and npm via `npm_config_*`/`--userconfig` with `cache=<writable>` + `offline=true`; restore locked; write nothing to `/work` (`RestoreAdditionalProjectSources` is repo-controlled and out of scope); in the phase loop translate copilot exit 43 → `git push origin "$WorkBranch"` then `exit 43` (terminates before the unconditional end-of-run push), keeping the existing exit-42 branch (REQ-3, REQ-5, RISK-3, RISK-6) `L`
- [x] 3.3 Add `tests/autopilot/ContainerOffline.Tests.ps1` (`test:Autopilot.ContainerOffline`): assert `launch-container.ps1` adds the `:ro` feed mount, `prepare-env-file.ps1` injects `AUTOPILOT_OFFLINE`/`AUTOPILOT_FEED`, and `container-entrypoint.sh` copies the feed, emits out-of-tree offline config (no `/work` writes), restores locked, and handles exit 43 (REQ-3, REQ-9) `M`

## Phase 4: Sandbox offline path
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 4.1 `launch-sandbox.ps1` mount + lifecycle: add `-FeedPath`; when set emit a read-only `MappedFolder` (`<ReadOnly>true</ReadOnly>`) mapping `FeedPath` → `C:\feed`; clear any stale session markers/sentinel before launch, then BLOCK polling the writable session dir for the bootstrap completion sentinel (with timeout) instead of fire-and-forget — edit via .NET `ReadAllText`/`WriteAllText` + `UnicodeEncoding`, matching literal `` `$ `` with single-quoted strings (REQ-4, RISK-2, RISK-5, RISK-7) `M`
- [x] 4.2 Sandbox bootstrap (inside the `launch-sandbox.ps1` here-string): when offline, copy `C:\feed` → a writable cache, emit OUT-OF-TREE NuGet + npm config (no `C:\work` writes) mirroring 3.2; on copilot exit 43 `git push` `$WorkBranch` then write `.autopilot-rebundle-needed` into the session dir; write the completion sentinel from a `trap`/`finally` so it ALWAYS fires — even if the bootstrap throws before completion — releasing the host poll instead of forcing a timeout (REQ-4, REQ-5, RISK-2, RISK-6) [after: 4.1] `M`
- [x] 4.3 `launch-sandbox.ps1` returns exit 43 when the rebundle marker is present after the sentinel poll completes; add `tests/autopilot/SandboxOffline.Tests.ps1` (`test:Autopilot.SandboxOffline`) reading the UTF-16 script with `Get-Content` asserting the `ReadOnly` `C:\feed` mount, out-of-tree offline config, sentinel poll, and the marker→43 path (REQ-4, REQ-9, RISK-2) [after: 4.2] `M`

## Phase 5: Agent and launcher loop
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 5.1 `autopilot.agent.md`: add an offline rebundle exception — when `AUTOPILOT_OFFLINE=true` and an offline restore fails on a missing package, stage only the package **manifests** (`package.json` / `*.csproj`), **never the lockfiles** (the offline agent can't regenerate a valid one — the host does), leave the step `[~]` (do not mark complete), make a rebundle-request commit, and `exit 43` (distinct from `@human` exit 42; never fetch from the network; never push; never write the marker or offline config). Document the resume contract (committed manifest + host-regenerated lock + `[~]` ⇒ continue) (REQ-5, RISK-3, RISK-6) [after: 3.2, 4.2] `M`
- [x] 5.2 `launch.ps1`: StrictMode-safe `offlinePackages` access + defaulting (absent → disabled; absent `maxRebundles` → 3; type-validate when `enabled`); factor dispatch into a function returning an int; when enabled and runtime ∈ {container, sandbox} prep the feed + pass `-FeedPath`; loop on exit 43 → `prepare-packages.ps1 -Branch $WorkBranch` (which regenerates + commits + pushes the lockfile) → relaunch — the re-prep must complete (lockfile pushed) **before** the relaunch clones — capped by `maxRebundles`; warn-and-ignore for `-Runtime host` (REQ-2, REQ-6, RISK-4) [after: 2.2, 3.1, 4.1, 5.1] `L`
- [x] 5.3 Add `tests/autopilot/RebundleLoop.Tests.ps1` (`test:Autopilot.RebundleLoop`) against the extracted dispatch function (subprocess fixtures with a mock orchestrator returning 43 then 0): asserts re-prep + relaunch, cap enforced, host-mode skip, and absent/disabled/missing-`maxRebundles` config no-op (REQ-6, REQ-9) [after: 5.2] `M`

## Phase 6: cip authoring changes
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 `interview-guide.md`: add an "Offline package bundling" question area — for autonomous container/sandbox plans, enumerate expected new packages and confirm they will be batched to minimize host round-trips (REQ-8) `S`
- [ ] 6.2 `plan-template.md`: add the optional `<!-- expected-packages: dotnet:<list>; npm:<list> -->` header marker with an inline legend (REQ-8) `S`
- [ ] 6.3 `drafting-guide.md`: add guidance to batch package-adding steps into a single early phase so the offline rebundle round-trip fires at most once (REQ-8) `S`

## Phase 7: Docs, design notes, registry, and validation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 7.1 Document the offline flow + exit-43-vs-42 round-trip + host-side loop ownership in autopilot `SKILL.md` (read-by-`/ci`) and the `ci` `SKILL.md` / `execution-guide.md` (REQ-7) [after: 5.2] `M`
- [ ] 7.2 Update design notes: `autopilot-execution.design.md` (offline feed, read-only mount + writable copy, exit-43 rebundle, `prepare-packages` in Script Inventory), `autopilot-skill.design.md` (`offlinePackages` config + launcher loop), `plan-workflow.design.md` (cip package-awareness) (REQ-9) [after: 7.1, 6.3] `M`
- [ ] 7.3 Register `prepare-packages.ps1` in `plugins/autopilot/plugin.json` `files[]` (plus dogfood); patch-bump `version` for `autopilot`, `continue-implementation`, `create-implementation-plan` (REQ-9) [after: 7.2] `S`
- [ ] 7.4 Run `Sync-Dogfood.ps1` then `Build-Registry.ps1` so `.github/` copies + `registry.json` hashes are current (REQ-9) [after: 7.3] `S`
- [ ] 7.5 Run `npm test` and `npm run eval` green; `review:cr` over the ci/cip docs confirms the exit-43-vs-42 round-trip is described (REQ-9, REQ-7) [after: 7.4] `M`

## Finalization (conditional)

- [ ] 8.1 Finalization gate — verify all typed evidence resolves, run `review:cr`, confirm design notes + registry in sync (REQ-9) @human `S`
