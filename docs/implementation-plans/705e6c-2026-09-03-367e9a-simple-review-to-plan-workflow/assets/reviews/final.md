## Source

0a3dffaee78f9d29354e2e04a907e94e9f89d717

## Scope

- Complete canonical branch delta 7209e56a9e9916903220f363092a87675ee9ca08...0a3dffaee78f9d29354e2e04a907e94e9f89d717 resolved by .github/agents/scripts/Get-ReviewScope.ps1 -Mode branch -IncludeDeleted: 695 paths (125 added, 237 modified, 2 renamed, 331 deleted; 28,114 insertions, 167,016 deletions).

## Completed tasks

- [x] Combined GPT-5.6 Sol whole-plan terminal review — complete
- [x] Claude Opus 5 independent whole-plan terminal pass — complete

## Findings

- Prior finding 1 — resolved: all registry payload hashes now use Git-clean canonical bytes and match the reviewed HEAD blobs.
- Prior finding 2 — resolved: update now installs absent unowned destinations and transactionally reconciles retired destinations while preserving modified residue.
- Prior finding 3 — resolved: host and Windows Sandbox launchers now run an explicit completion-only invocation after all phases close, including all-closed resumes.
- Prior finding 4 — resolved: Get-SiHarvest resolves the source plan by canonical plan identity inside the recorded source commit, surviving active-to-archive moves.
- Prior finding 5 — resolved: Write-RecentLearning rejects linked or reparse-point repository, parent, target, and temporary path components before replacement.
- Prior finding 6 — resolved: /ci restores the hard Kind: epic host-only route to Invoke-EpicAutopilot.ps1.
- Prior finding 7 — resolved: the obsolete schemas/architecture/** scaffold declaration was removed and the path is documented as optional repository-owned input.
- Prior finding 8 — resolved: focused contract assertions accept the retained attacker/untrusted-input four-link security wording.
- Prior finding 9 — resolved: criteria comparison now uses Git-filter-aware diff semantics, so checkout-only line-ending conversion is ignored.
- Prior finding 10 — resolved: Get-DesignNoteCompactionContext requires the canonical RepoRoot and every documented caller supplies it.
- [P1] plugins/autopilot/scripts/plan-dispatch.sh:443-455 suppresses completion-only whenever the final incomplete phase is selected, while plugins/autopilot/agents/autopilot.agent.md:37-40 says a phase target never finalizes; a container whole-plan run that executes the last phase therefore cannot perform terminal review, compaction, learning publication, or archival and eventually exhausts close handoffs. Always append completion-only after successful whole-plan phase execution and stop treating phase:<final> as the finalization owner.
- [P1] scripts/skalary/DirectWorkflow.psm1:151-159,204-206 compares the baseline only with the working tree, so a protected criterion or confirmation marker changed only in the index is accepted and can be committed by execution. Validate indexed plan/criteria state independently with git diff --cached or equivalent, while retaining the Git-filter-aware working-tree check.
- [P2] plugins/autopilot/agents/autopilot.agent.md:37-55 removed the headless /pfb queue step and the /ci archival-gate offer even though plugins/self-improvement/skills/pfb/assets/queue-guide.md:5-8 still defines that non-blocking integration; headless completion silently loses the operator-feedback question, as the focused assertions at tests/skalary/FeedbackQueue.Tests.ps1:164-171,264-273 demonstrate. Restore the reachable queue/offer contract or retire the integration consistently.

## Verdict

findings
