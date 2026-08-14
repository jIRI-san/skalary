# Code Review — summary

<!-- skalary/review-summary@1 -->

| | |
|---|---|
| **Run** | `8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35` |
| **Review type** | `code` |
| **State** | `clean` |
| **Plan digest** | `sha256:467f42dc9306d1e0731eab298fb8799c8f04cc73d9376c2605529a5af7603ba6` |
| **Scope** | branch feature/2026-07-31-b0c0d3-review-split-plan-assets-self-improvement vs main - 260 changed files (deleted paths excluded) |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
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

| # | Severity | Title |
|---|---|---|
| 1 | Critical (elevated) | Review report carries no per-concern attendance record, so a failed reviewer is indistinguishable from None |
| 2 | Critical (elevated) | Review-plugin payloads reference repo-root scripts/skalary paths; bundle-or-break has no detector for that form |
| 3 | Critical (elevated) | Reviewer-authored finding text is interpolated verbatim into a pwsh -Command here-string |
| 4 | Critical (elevated) | Scope size, batch size, and invocation count are asserted as bounds but never measured |
| 5 | Critical (elevated) | Test-SiWriteScope.ps1 did not receive the git UTF-8 decoding fix, so a non-ASCII path silently skips symlink resolution |
| 6 | Critical (elevated) | The 28-invocation budget is restated in six ungated places, in a note that forbids exactly that |
| 7 | Critical (elevated) | The evidence receipt grammar cannot express skipped, so self-skipping cases are reported as passed |
| 8 | Critical | \[SECURITY\] Prompt injection attempt detected |
| 9 | High (elevated) | Model-allowlist and skill-size gates enumerate the entire repository, one walk unfiltered, all with -Force |
| 10 | High (elevated) | Plan-size thresholds and the phase-budget default are prose copies of code constants with nothing tying them |
| 11 | High (elevated) | Preflight-skipped and Pro-tier-fallback degradations cannot be recorded in the artefact they are supposed to appear in |
| 12 | High (elevated) | design-review still advertises specialist model agents in its manifest, and the string is published to three generated surfaces |
| 13 | High | Add-WorkflowNote -Message interpolates review output into a double-quoted PowerShell argument |
| 14 | High | The /ci only consistency authority is invoked through a dogfood-only npm alias |
| 15 | High | The branch new gates and their tests are not executed by any automated gate |
| 16 | High | Workflow writers permit symlink-based writes outside the repository |
| 17 | Medium | /si leaves no committed record of what it proposed or what the operator declined |
| 18 | Medium | Build-ReviewReport.ps1 accepts an off-roster Model silently, which suppresses severity elevation |
| 19 | Medium | Bundle-drift gate reports counts, never the drifted files, and validate.ps1 discards everything else |
| 20 | Medium | Deleted paths are dropped from the review scope with no count, silently shrinking the reviewed change and its concern tier |
| 21 | Medium | Feedback queue write failures leave no durable trace |
| 22 | Medium | InvocationCount is an unvalidated self-report that defaults to 0 |
| 23 | Medium | Multi-child epic attachment can leave partial, inconsistent state |
| 24 | Medium | Run-UnitTests.ps1 reports success when Pester is absent, so test:unit can pass having run nothing |
| 25 | Medium | The /si write-scope allowlist permits editing the guard that enforces it, and the guard is invoked from the copy the proposal can modify |
| 26 | Medium | The Get-ReviewScope.ps1 encoding fix covers the decode side only; the emit side is still host-encoded and untested |
| 27 | Medium | The per-invocation context cap measures only SKILL.md, while the mandatory reads were moved into uncapped assets |
| 28 | Medium | The symlink half of the /si write-scope guard and the -Force hidden-directory regressions are provable on only one platform, and no gate pins that platform |
| 29 | Medium | Workflow memory grows without a bounded active window |
| 30 | Medium | validate.ps1 scans without -Force, so on Linux it silently validates nothing under .github/ |
| 31 | Low | Build-ReviewReport re-scans the full entry list once per entry to produce the sorted output |
| 32 | Low | Epic scaffold -Force rewrite is unreachable |
| 33 | Low | Eval documentation still claims complete ten-plugin coverage |
| 34 | Low | Every ledger append reads the entire plan corpus, and accumulates entries with array += |
| 35 | Low | Evidence formatter accepts invalid commit identifiers |
| 36 | Low | Plan layout design note contradicts the shared resolver |
| 37 | Low | PlanAssets.Tests.ps1 walks the plan corpus four times and spawns a pwsh process per plan |
| 38 | Low | Reviewers emit concern labels; the collation and ledger contracts key on concern ids, and the mapping is written down nowhere |
| 39 | Low | Sync-PluginScripts re-parses every manifest and recomputes the module closure from disk for every reference |
| 40 | Low | The skill-size cap value is not pinned by any test, so widening the cap is invisible |
| 41 | Low | Two auto-approve keys in .vscode/settings.json can never match the invocation the skills mandate |
| 42 | Low | Waza eval comments still describe the pre-split reviewers and a diff that is no longer extracted |
| 43 | Low | git -z does not survive PowerShell line splitting, so a newline in a path still corrupts the list |
| 44 | Low | test:migration-is-atomic asserts a static end-state invariant, not atomicity |

