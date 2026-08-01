## Capture
Phase: 1

- [1.3] [src:note] dr: a served model cannot attest its own identity, so self-reported model names are never a valid downgrade detector
- [1.3] [src:note] dr: dircount evidence markers count files and subdirs recursively and can be green before any work starts
- [1.3] [src:note] dr: plan parsing lives in Get-PlanMetadata, so parser changes wired at the Test-Plan boundary silently break Get-PlanState
- [1.3] [src:note] dr: VS Code qualified model names and Copilot CLI bare slugs must never be normalized to one format
- [8.2] [src:note] dr: .github is not a document tree - same-repo PR branches execute workflows with repository secrets at PR-open time, before human review
- [1.6] [src:note] dr: /ci picks the first incomplete step in document order, so step order in the file IS the execution order - a missing after edge means the wrong order runs
- [10.3] [src:note] dr: registry.schema.json sets additionalProperties false on plugin entries, so any new manifest field needs both schemas plus Build-Registry to reach consumers
- [4.4] [src:note] dr: recurring defect class - a plan asserting a control that nothing enforces; check every cap, block and threshold against its actual implementation

## Capture
Phase: 2

No entries for this phase.

## Capture
Phase: 3

No entries for this phase.

## Capture
Phase: 4

No entries for this phase.

## Capture
Phase: 5

- [-] Registry/marketplace must be rebuilt after every payload edit: a stale sha256 fails Install-Plugin but validate.ps1 does not catch it
- [-] Build-Registry appends one trailing blank line to README on every catalog change (unbounded growth, pre-existing); candidate cleanup for a hygiene step

## Capture
Phase: 6

No entries for this phase.

## Capture
Phase: 7

No entries for this phase.

## Capture
Phase: 8

No entries for this phase.

## Capture
Phase: 9

No entries for this phase.

## Capture
Phase: 10

- [-] npm run eval: 116 pass / 2 fail. Both remaining failures (HumanDoc-Generated malformed-JSON, Staleness-FlagsDrift) predate this branch and sit in New-ArchHumanDoc/Test-ArchDocFreshness, which this plan never touches.
- [-] CRLF re-materialize was a no-op: git ls-files --eol reports i/lf w/lf across plugins/ and .github/, so .gitattributes normalization already holds.
- [-] Intent re-anchor: plan folders hold only plan.md, cr/dr review by concern over a file list, and pfb/si turn feedback and learnings into never-auto-merged proposals — all three desired outcomes delivered. Non-goals held: no existing or archived plan was migrated, no cross-repo PR automation, no claim to detect a served-model downgrade.
- [-] Plan crosscheck: 107 markers, 105 pass. The only two non-passing are review:dr (REQ-9) and review:cr (REQ-17), both unrun by construction — step 10.7 is the operator gate that runs them in chat. No marker failed.
