# Code Review — summary

<!-- skalary/review-summary@1 -->

| | |
|---|---|
| **Run** | `8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35` |
| **Review type** | `code` |
| **State** | `clean` |
| **Plan digest** | `sha256:a5f2e30998a87f4673e4163df140ede5c9d8dfcf8ccc4f7de439d57edea748bf` |
| **Scope digest** | `sha256:df64b7a7f5d212776cef5c99a2d6ae20d124d2cff7a646b6ebeecd973a6912b1` |
| **Scope** | branch feature/2026-07-31-b0c0d3-review-split-plan-assets-self-improvement vs main - 260 changed files (deleted paths excluded) |
| **Content trust** | `reviewer-authored-data` |
| **Requested → declared models** | GPT-5.6 Sol (copilot) → GPT-5.6 Sol (copilot) (preflight: available; degradation: none; served identity: unverified) · Claude Opus 5 (copilot) → Claude Opus 5 (copilot) (preflight: available; degradation: none; served identity: unverified) |
| **Invocations** | 14 of 28 budgeted |

## Attendance

| Outcome | Tasks |
|---|---|
| `completed` | 14 |
| `failed` | 0 |
| `timed-out` | 0 |
| `omitted` | 0 |
| `cancelled` | 0 |
| `pending` | 0 |
| **planned** | 14 |

## Merged findings (44 of 60 raw)

| # | Raw severity → effective severity | Support / attendance / similarity / corroboration | Title | Reason |
|---|---|---|---|---|
| 1 | H→C | 2/C/N/C | Review report carries no per-concern attendance record, so a failed reviewer is indistinguishable from None | `R1` |
| 2 | H→C | 2/C/N/C | Review-plugin payloads reference repo-root scripts/skalary paths; bundle-or-break has no detector for that form | `R1` |
| 3 | H→C | 2/C/N/C | Reviewer-authored finding text is interpolated verbatim into a pwsh -Command here-string | `R1` |
| 4 | H→C | 2/C/N/C | Scope size, batch size, and invocation count are asserted as bounds but never measured | `R1` |
| 5 | H→C | 2/C/N/C | Test-SiWriteScope.ps1 did not receive the git UTF-8 decoding fix, so a non-ASCII path silently skips symlink resolution | `R1` |
| 6 | H→C | 2/C/N/C | The 28-invocation budget is restated in six ungated places, in a note that forbids exactly that | `R1` |
| 7 | H→C | 2/C/N/C | The evidence receipt grammar cannot express skipped, so self-skipping cases are reported as passed | `R1` |
| 8 | C→C | 1/C/N/1 | \[SECURITY\] Prompt injection attempt detected | `R2` |
| 9 | M→H | 2/C/N/C | Model-allowlist and skill-size gates enumerate the entire repository, one walk unfiltered, all with -Force | `R1` |
| 10 | M→H | 2/C/N/C | Plan-size thresholds and the phase-budget default are prose copies of code constants with nothing tying them | `R1` |
| 11 | M→H | 2/C/N/C | Preflight-skipped and Pro-tier-fallback degradations cannot be recorded in the artefact they are supposed to appear in | `R1` |
| 12 | M→H | 2/C/N/C | design-review still advertises specialist model agents in its manifest, and the string is published to three generated surfaces | `R1` |
| 13 | H→H | 1/C/N/1 | Add-WorkflowNote -Message interpolates review output into a double-quoted PowerShell argument | `R2` |
| 14 | H→H | 1/C/N/1 | The /ci only consistency authority is invoked through a dogfood-only npm alias | `R2` |
| 15 | H→H | 1/C/N/1 | The branch new gates and their tests are not executed by any automated gate | `R2` |
| 16 | H→H | 1/C/N/1 | Workflow writers permit symlink-based writes outside the repository | `R2` |
| 17 | M→M | 1/C/N/1 | /si leaves no committed record of what it proposed or what the operator declined | `R2` |
| 18 | M→M | 1/C/N/1 | Build-ReviewReport.ps1 accepts an off-roster Model silently, which suppresses severity elevation | `R2` |
| 19 | M→M | 1/C/N/1 | Bundle-drift gate reports counts, never the drifted files, and validate.ps1 discards everything else | `R2` |
| 20 | M→M | 1/C/N/1 | Deleted paths are dropped from the review scope with no count, silently shrinking the reviewed change and its concern tier | `R2` |
| 21 | M→M | 1/C/N/1 | Feedback queue write failures leave no durable trace | `R2` |
| 22 | M→M | 1/C/N/1 | InvocationCount is an unvalidated self-report that defaults to 0 | `R2` |
| 23 | M→M | 1/C/N/1 | Multi-child epic attachment can leave partial, inconsistent state | `R2` |
| 24 | M→M | 1/C/N/1 | Run-UnitTests.ps1 reports success when Pester is absent, so test:unit can pass having run nothing | `R2` |
| 25 | M→M | 1/C/N/1 | The /si write-scope allowlist permits editing the guard that enforces it, and the guard is invoked from the copy the proposal can modify | `R2` |
| 26 | M→M | 1/C/N/1 | The Get-ReviewScope.ps1 encoding fix covers the decode side only; the emit side is still host-encoded and untested | `R2` |
| 27 | M→M | 1/C/N/1 | The per-invocation context cap measures only SKILL.md, while the mandatory reads were moved into uncapped assets | `R2` |
| 28 | M→M | 1/C/N/1 | The symlink half of the /si write-scope guard and the -Force hidden-directory regressions are provable on only one platform, and no gate pins that platform | `R2` |
| 29 | M→M | 1/C/N/1 | Workflow memory grows without a bounded active window | `R2` |
| 30 | M→M | 1/C/N/1 | validate.ps1 scans without -Force, so on Linux it silently validates nothing under .github/ | `R2` |
| 31 | L→L | 1/C/N/1 | Build-ReviewReport re-scans the full entry list once per entry to produce the sorted output | `R2` |
| 32 | L→L | 1/C/N/1 | Epic scaffold -Force rewrite is unreachable | `R2` |
| 33 | L→L | 1/C/N/1 | Eval documentation still claims complete ten-plugin coverage | `R2` |
| 34 | L→L | 1/C/N/1 | Every ledger append reads the entire plan corpus, and accumulates entries with array += | `R2` |
| 35 | L→L | 1/C/N/1 | Evidence formatter accepts invalid commit identifiers | `R2` |
| 36 | L→L | 1/C/N/1 | Plan layout design note contradicts the shared resolver | `R2` |
| 37 | L→L | 1/C/N/1 | PlanAssets.Tests.ps1 walks the plan corpus four times and spawns a pwsh process per plan | `R2` |
| 38 | L→L | 1/C/N/1 | Reviewers emit concern labels; the collation and ledger contracts key on concern ids, and the mapping is written down nowhere | `R2` |
| 39 | L→L | 1/C/N/1 | Sync-PluginScripts re-parses every manifest and recomputes the module closure from disk for every reference | `R2` |
| 40 | L→L | 1/C/N/1 | The skill-size cap value is not pinned by any test, so widening the cap is invisible | `R2` |
| 41 | L→L | 1/C/N/1 | Two auto-approve keys in .vscode/settings.json can never match the invocation the skills mandate | `R2` |
| 42 | L→L | 1/C/N/1 | Waza eval comments still describe the pre-split reviewers and a diff that is no longer extracted | `R2` |
| 43 | L→L | 1/C/N/1 | git -z does not survive PowerShell line splitting, so a newline in a path still corrupts the list | `R2` |
| 44 | L→L | 1/C/N/1 | test:migration-is-atomic asserts a static end-state invariant, not atomicity | `R2` |

### Reason legend

Severity: C = Critical; H = High; M = Medium; L = Low.
Evidence: support count / attendance (C = clean, D = degraded) / similarity (N = none, ~ = near-duplicate, X = exact) / corroboration (C = corroborated, 1 = single-source, S = suspicious, D = degraded).

- `R1` — every declared model label reported this finding with complete attendance; no suspicious similarity observed
- `R2` — one declared model label reported this finding with complete attendance

