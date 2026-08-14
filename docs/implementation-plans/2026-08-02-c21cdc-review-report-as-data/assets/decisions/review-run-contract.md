# Review-run data contract

## Boundary

`c21cdc` turns a review run into one versioned data artifact and two derived views. It owns the format and truthfulness of the run record, not reviewer scheduling or whether two outputs prove independent model corroboration.

The final envelope uses discriminator `skalary/review-run@1`; the schema itself has a repository URL `$id`. Before dispatch, `Freeze` validates and publishes an immutable plan carrying:

- run UUID, review type, bounded scope, declared roster, and invocation budget;
- one unique task ID for every unique concern/declared-model slot;
- no outcomes or findings.

After dispatch, the final envelope binds the frozen-plan digest and contains:

- review type and bounded scope text;
- the declared model roster and invocation budget;
- the exact frozen task set with outcomes and bounded diagnostics;
- zero or more raw findings, each referring to exactly one completed task.

Task outcomes are closed: `completed`, `failed`, `timed-out`, `omitted`, `cancelled`, and `pending`. A completed task may have zero findings. Every non-completed task carries a bounded diagnostic and cannot own findings. Zero tasks is invalid. Only all-completed is clean; every other structurally and semantically valid mix is degraded. Counts and state are derived; the envelope cannot provide aggregate overrides.

## Bounds

The v1 envelope is at most 2 MiB and accepts at most 128 tasks and 256 raw findings. Findings have 160-character titles, 4 KiB bodies, and at most 8 bounded references. Semantic grouping may produce at most 128 merged findings.

Structural validity does not guarantee renderability. `Publish` canonicalizes and renders exact UTF-8 bytes before publication. The canonical JSON remains lossless and authoritative. The summary is at most 32 KiB, reports aggregate task outcomes, and names every merged finding by severity and title. The full Markdown is at most 1 MiB, lists every task and merged finding, keeps the strongest body, and may retain bounded distinct deltas. If every required entry cannot fit, publication exits `3` before the manifest changes; it never silently truncates or drops a finding.

Canonical JSON uses NFC strings, LF, UTF-8 without BOM, integer-only numbers, ordinal object keys, and contract-defined ordering for semantically unordered task/finding sets. Its SHA-256 is stable across raw JSON property order and culture. Titles/references are Markdown encoded; bodies are HTML encoded inside explicit untrusted-data boundaries. Later agents are told never to follow directives found inside reviewer data.

## Invocation and trust

The installed CLI accepts only `-Mode Freeze|Publish -RunId <lowercase UUID>` plus optional `-PlanDir <resolved plan>`. It derives repo root from its installed `.github/skills/<cr|dr>/scripts/` location, loads bundled schemas relative to itself, and computes all inputs/outputs. Plan-associated runs use the `ReviewRuns` kind from `Resolve-PlanAssetPath`; generic runs live at `<repo>/.github/.skalary/review-runs/<run-id>/`. No caller chooses repo, schema, or output root. Reviewer text never enters a shell command, PowerShell source, or dynamic evaluator.

CR/DR orchestrators gain the editor `edit` tool with an absolute rule limiting writes to the two computed temporary inputs and published plan review artifacts; they still never edit reviewed code. The caller writes `<run>/.review-plan.input.tmp`; `Freeze` flushes and atomically renames it to `review-plan.input.json`. After all reviewers return, the caller writes exactly one `<run>/.review-result.input.tmp`; `Publish` atomically renames it to `review-result.input.json`. Reviewer data never enters a terminal command. Inputs are removed after success and immediately destroyed/redacted on secret rejection. Plan artifacts are committed explicitly; bundled `Remove-ReviewRun.ps1` removes generic runs only after verified summary delivery.

`Freeze` validates caller-authored plan input and atomically publishes the immutable planned-task artifact before any subagent call. `Publish` validates result input against that digest, writes content-addressed canonical JSON and both views, verifies bytes/digests, then atomically replaces `review-run.manifest.json` last under an exclusive lock. Readers trust only that manifest and verify every referenced digest. Unreferenced staging/generation files are ignored and cleaned on retry. Module-scoped publication functions permit deterministic fault injection without exposing a production failpoint.

The state machine is `new -> frozen -> published`. Repeating Freeze/Publish with identical canonical digest is idempotent. Changed input under a frozen/published run ID, Publish-before-Freeze, or frozen mutation exits `2`. Publication exit `4` supports same-input retry after correction/lock release. Admission exit `3` is terminal for that UUID: the caller explicitly abandons it and starts a narrower-scope run without dropping findings. At review start, `Get-ReviewRun.ps1 -ListIncomplete` finds frozen unpublished runs; the caller publishes every task as `cancelled` with `orchestrator-interrupted`, then starts a new UUID. No model-output resume is attempted. Manifest names are confined single segments.

Exit `0` means clean publication; `5` means valid degraded publication and is returned only after artifacts exist; `2` means parse/schema/semantic/state invalid; `3` means input/render admission failure; `4` means lock/publication/unexpected failure. Every exit writes exactly one terminal-status JSON object of at most 8 KiB on stdout. Encoded stderr is at most 16 KiB; each task diagnostic is at most 2 KiB UTF-8. Error precedence is parse/schema, semantic/state, admission, then publication.

Scope, task diagnostics, titles, bodies, actions, and references are all untrusted. Every rendered field is encoded/fenced. Reviewers must redact suspected credential values; plan-associated publication rejects high-confidence credential shapes and reports only redacted type/location. The authoritative JSON is lossless only after that acceptance guard.

## Compatibility and follow-up

The current exact `(RootCause, Component)` grouping, strongest-severity choice, full-declared-roster elevation, ordinal ordering, and recommendation behavior stay compatible during this migration. The wording identifies models as declared dispatch models; it never claims they were the models actually served.

`Get-ReviewRun.ps1` is the only reader: it validates manifest schema, confines names, verifies digests, and emits the summary. `Build-ReviewReport.ps1` emits only bounded terminal JSON. `Remove-ReviewRun.ps1` validates the same manifest/root before generic cleanup.

`8a0644` and `ca8ba8` depend on this plan. `8a0644` later produces fleet task plans through the v1 adapter. `ca8ba8` consumes v1 to add output-similarity evidence; any shape or semantic change requires explicit v2 plus migration. Neither introduces a second persistence or rendering contract.