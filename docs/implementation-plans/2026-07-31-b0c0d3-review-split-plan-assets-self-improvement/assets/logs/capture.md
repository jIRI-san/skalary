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
