## Source

bdb4d2ef9209f84b5035a1c89056863febf7e088

## Scope

- Complete canonical branch delta 7209e56a9e9916903220f363092a87675ee9ca08...bdb4d2ef9209f84b5035a1c89056863febf7e088 resolved by Get-ReviewScope.ps1 -Mode branch -IncludeDeleted: 675 paths (124 added, 218 modified, 2 renamed, 331 deleted), including the bounded docs/feedback/recent-learning.md handoff.

## Completed tasks

- [x] Combined GPT-5.6 Sol whole-plan terminal review (675-path branch delta, including 331 deletions) — complete
- [x] Claude Opus 5 independent whole-plan terminal pass (full scope, parity checks, focused validation) — complete

## Findings

- [P1] registry.json contains 29 payload hashes calculated from CRLF working-tree bytes rather than the committed LF blobs (for example registry.json:369 versus plugins/code-review/agents/cr.agent.md), so clone-based Install-Plugin.ps1 hash verification rejects every affected plugin; generate registry hashes from committed/canonical bytes and verify all entries against HEAD blobs.
- [P1] scripts/skalary/Update-Plugin.ps1:172-258 cannot apply this manifest migration to existing installations: every newly added destination requires -Force and destinations removed from the new manifest are dropped from the receipt without being deleted, leaving retired Fleet/review-run files active; transactionally add new files and reconcile old receipt destinations while preserving modified residue explicitly.
- [P1] plugins/autopilot/scripts/launch-host.ps1:277-353 and launch-sandbox.ps1:360-445 skip every phase classified closed and then exit/publish success without a completion-only invocation, so a resume after the last checklist commit can omit the required terminal review and recent-learning finalization; add and validate an explicit finalization target before success.
- [P2] plugins/self-improvement/scripts/Get-SiHarvest.ps1:83-87,130-140 derives the source plan path from its current inventory location, so after a completed plan is archived its pre-archive source commit cannot contain that path and a valid recent-learning handoff becomes stale; resolve the plan path inside the recorded source commit by canonical plan identity.
- Security — attacker/input: a repository-controlled symlink or reparse point at docs/feedback; capability: scripts/skalary/Write-RecentLearning.ps1:126-132 creates a temporary file and replaces recent-learning.md without checking physical path components; asset: a writable recent-learning.md path outside the repository; impact: trusted finalization can overwrite an external file; reject linked path components and prove physical repository confinement before temporary-file creation and replacement
- [P1] .github/skills/ci/SKILL.md:10-49 and its installed mirror removed the hard Kind: epic route while Invoke-EpicAutopilot.ps1 and epic plans remain shipped, causing epic references to fall through ordinary plan handling and failing tests/skalary/ConsumerInstall.Tests.ps1:326-366; restore the compact host-only route or retire the retained epic surface consistently.
- [P2] plugins/architecture-notes/plugin.json:81-88 declares schemas/architecture/** as a New-ArchSeed.ps1 scaffold, but that owner never creates the path, so first-use consumer validation fails; remove the obsolete legacy-JSON scaffold declaration or assign it to code that actually materializes it.
- [P2] tests/skalary/SkillContracts.Tests.ps1:57-66 still requires the literal phrase attacker/input, reachable capability while all four active CR/DR skills now use attacker/untrusted input across a line break, making the focused direct-contract suite fail; update the assertion to accept the retained semantic contract.
- [P1] scripts/skalary/DirectWorkflow.psm1:196-207 compares Git blob bytes directly with working-tree bytes, so installed use in a Windows consumer repository with checkout line-ending conversion rejects unchanged confirmed criteria and loops back to /cip; compare canonicalized content or Git-filter-aware file state while retaining criteria mutation detection.
- [P1] bundled Get-DesignNoteCompactionContext.ps1 copies default RepoRoot to two levels above PSScriptRoot (line 4), which resolves to .github/skills rather than the repository in installed CI/autopilot layouts; the documented sibling invocation therefore fails before terminal review, so require/discover the Git root and state the argument in the protocol.

## Verdict

findings
