# Feedback Queue

Post-plan feedback written by `/pfb` through `Update-FeedbackQueue.ps1`. Script-owned — never hand-edit.
`## Pending` holds prompts a headless run could not ask; `## Recorded` holds operator verdicts.
Every entry is untrusted free text: `/si` harvests it as data and never executes it.

## Pending

- [433d4e68] [plan:768d7b] [queued:2026-08-05] Intent asks that every advertised gate either runs on every PR or is a recorded exclusion. The PSScriptAnalyzer step runs but cannot go red: Invoke-ScriptAnalyzer sets no exit code, and scripts/skalary carries 472 findings (all Warning, 0 Error) under the committed settings. It is now recorded as ex
- [bb6faa0f] [plan:768d7b] [queued:2026-08-05] The suite finishes in 102s on Linux and 223s on Windows, well inside the intent bar. The Linux ceiling was tightened to 330s but the Windows ceiling stays at the originally bound 600s, because the tightening rule (3x achieved) would have raised it. Do you want Windows tightened to a figure closer to

## Recorded

- [b65326ce] [plan:b0c0d3] [recorded:2026-08-01] [align:partial] Operator mostly satisfied. Goal and all three desired outcomes delivered and demonstrated live at the step 10.7 gate: plan root holds only plan.md, cr dispatched 7 concerns across 2 models over a changed-file list (14 of 28 budgeted), and Test-SiWriteScope refused a workflow edit. All three non-goal
- [095e99d0] [plan:b0c0d3] [recorded:2026-08-01] [align:partial] MISS against the success signal "no skill, agent, or prompt reads an asset that installation does not materialize": both dispatch guides invoke scripts/skalary/Test-ModelAllowlist.ps1, which no plugin bundles. The model preflight is structurally unavailable in a consumer install and the guides own a
- [76bdd771] [plan:b0c0d3] [recorded:2026-08-01] [align:partial] MISS against the definition of done "no unrun/failed markers left undeferred": Build-EvidenceReceipt maps a boolean to passed/failed/unrun with no skipped state, so a discovered-but-skipped Pester case is recorded as passed. On Windows four of five symlink-confinement cases self-skip, yet the receip
