# Review-run lifecycle (shared by `/cr` and `/dr`)

This guide owns the caller contract for `skalary/review-run@1`. Both installed copies are
byte-identical. The writer, reader, and cleanup scripts are bundled under
`.github/skills/<skill>/scripts/`.

## Runtime prerequisite

The installed writer requires PowerShell 7.6 or newer. Native
`Test-Json -SchemaFile` provides the draft-2020-12 validation boundary; no vendored validator or
package fallback exists. Consumer environments must provision PowerShell 7.6+ before review
dispatch. If the host lacks the required version or schema capability, Freeze returns bounded exit
`2` and the orchestrator stops before any reviewer runs.

## Absolute write boundary

The orchestrator's `edit` tool may write **only** these two files for the UUID it allocated:

- `<run-root>/.review-plan.input.tmp`
- `<run-root>/.review-result.input.tmp`

It must never edit reviewed code, the reviewed plan, fixed input names, manifests, generated
artifacts, or any other path. Create complete UTF-8 JSON with `edit`, then use one fixed local rename
to move the matching temporary file onto `review-plan.input.json` or `review-result.input.json`.
Reviewer text never appears in a terminal command, PowerShell source, or command argument.

Before `New-Item`, `edit`, or a rename, invoke the engine-owned read-only preflight:

```powershell
.github/skills/<skill>/scripts/Get-ReviewRun.ps1 -Prepare -RunId <uuid> [-PlanDir <plan>]
```

Use only the returned `runRoot`; never derive a generic or plan layout in the caller. `Prepare`
rejects every reparse ancestor/leaf before plan inventory or layout parsing and does not create the
directory. Create exactly that returned directory, then author the temporary input. Freeze never
creates a missing run root and rejects a caller that skipped initialization.

## Start: abandon interrupted runs

Before allocating a new UUID, run `Get-ReviewRun.ps1 -ListIncomplete` with the same optional
`-PlanDir`. For every returned UUID:

1. Read its sole content-addressed frozen plan.
2. Preserve every identity field and task slot.
3. Write one result input with every task outcome `cancelled`, diagnostic
   `orchestrator-interrupted`, and no findings.
4. Publish once. Read and surface both the verified summary and full detail on exit `5`.

Never resume missing outputs or reuse an interrupted run for the new review.

## Freeze before dispatch

Allocate one lowercase UUID. Build the complete task matrix from the selected concerns and the
declared dispatch roster. Stable task ids are `<concern>-m<one-based-roster-index>`. Write:

```json
{
  "schema": "skalary/review-plan@1",
  "runId": "<uuid>",
  "reviewType": "<code|design>",
  "contentTrust": "reviewer-authored-data",
  "scope": "<bounded description>",
  "scopeAuthority": {
    "mode": "branch",
    "base": "<base commit identity>",
    "head": "<head commit identity>",
    "paths": [{ "path": "<canonical repo-relative path>", "status": "modified" }]
  },
  "roster": ["<declared dispatch model>"],
  "modelSelection": [{
    "requested": "<requested model label>",
    "declared": "<declared dispatch label>",
    "preflight": "available",
    "degradation": "none",
    "servedIdentity": "unverified"
  }],
  "invocationBudget": 28,
  "tasks": [
    { "taskId": "security-m1", "concern": "security", "model": "<model>" }
  ]
}
```

For design review, use `scopeAuthority.mode = "design"` and include a `designSource` with `kind`,
canonical repository-relative `path`, and SHA-256 `digest`; `paths` names the reviewed plan/design
files. Freeze canonicalizes path records and adds the engine-owned `scopeAuthority.digest`. Read the
frozen plan and use its ordered path records, source identities, scope digest, model selection, and
task slots as the complete dispatch payload. No out-of-band path list may widen or narrow it.

Atomically rename the temporary plan onto the fixed input, then invoke the installed writer in this
exact argument order:

```powershell
.github/skills/<skill>/scripts/Build-ReviewReport.ps1 -Mode Freeze -RunId <uuid> [-PlanDir <plan>]
```

Freeze must return exit `0` before any reviewer dispatch. Exit `2` aborts invalid input; exit `3`
abandons that UUID and restarts with a narrower scope; exit `4` may retry the identical input only
after correcting the lock/publication fault. No other exit is valid.

## Independent dispatch and in-memory collection

Dispatch every frozen task exactly once. Do not show one reviewer's output to another reviewer, use
it to prime a later prompt, suppress a task because an earlier task found the same issue, or dedupe
before publication. Keep each returned section and task outcome in memory until all tasks terminate.

Map successful task output to `completed`, including a legitimate `None.` result. Map failures to the
specific terminal outcome (`failed`, `timed-out`, `omitted`, or `cancelled`) with a bounded diagnostic.
Only completed tasks may own findings.

Reviewers and the orchestrator must redact any suspected credential value before it enters the
result. Preserve only the credential type and source location. The engine independently rejects and
destroys plan-associated input that still contains a high-confidence credential shape.

## Publish once

Read the `sha256:...` value from `<run-root>/.review-run.frozen`. Build one result preserving the
frozen identity fields and exact task slots:

```json
{
  "schema": "skalary/review-run@1",
  "runId": "<uuid>",
  "reviewType": "<code|design>",
  "contentTrust": "reviewer-authored-data",
  "scope": "<same frozen scope>",
  "scopeAuthority": { "<exact frozen authority including digest>": "..." },
  "roster": ["<same frozen roster>"],
  "modelSelection": [{ "<exact frozen model state>": "..." }],
  "invocationBudget": 28,
  "planDigest": "sha256:<frozen digest>",
  "tasks": [
    {
      "taskId": "security-m1",
      "concern": "security",
      "model": "<same model>",
      "outcome": "completed"
    }
  ],
  "findings": [
    {
      "taskId": "security-m1",
      "severity": "High",
      "title": "<one-line title>",
      "body": "<reviewer-authored data>",
      "references": ["<file or plan reference>"]
    }
  ]
}
```

Do not hand-build Markdown. Write and atomically rename the single result input, then invoke Publish
once in the same exact argument order as Freeze. Handle the terminal status:

| Exit | Required caller behavior |
|---|---|
| `0` | Read and deliver the verified summary with `-View Summary`, then deliver or explicitly surface the verified full detail with `-View Full`; preserve plan artifacts, then remove a generic run. |
| `5` | Read and deliver the degraded summary and verified full detail with `-View Full`, including task diagnostics, before propagating non-success; remove a generic run only after both are delivered. |
| `2` | Abort as invalid, surface bounded diagnostics, and preserve existing authority. |
| `3` | Terminal for this UUID. Read verified admission state. If `restartable` is false, stop. Otherwise create at most 16 ordered child partitions in the sole allowed restart generation, preserving the parent tasks/model state and distributing every parent finding exactly once. |
| `4` | Surface the lock/publication failure; retry the same UUID and unchanged input only after the fault is corrected. |

Use `Get-ReviewRun.ps1 -View Summary|Full` as the only reader. Both modes verify the complete
manifest, every digest, encoding, and the selected role's byte bound. A reader failure is a failed
review and must not trigger cleanup. After verified summary and full-detail delivery, use
`Remove-ReviewRun.ps1` for generic runs only. Plan runs
retain `review-run.manifest.json` and every digest-bound artifact for commit/evidence.

Read admission metadata with `Get-ReviewRun.ps1 -ReadAdmission -RunId <parent>`. Each child plan/result
carries `restart` with that parent id/digest, `restartOrdinal: 1`, and its ordered partition index/count.
After every child publishes, `Get-ReviewRun.ps1 -VerifyAdmissionRollup -RunId <parent>` must return
`state: verified`; it rejects missing/duplicate partitions, scope gaps, and any changed or omitted raw
finding. There is no second restart generation.

The summary carries `contentTrust: reviewer-authored-data` structurally. Render its verified bytes
verbatim and put any operator-facing handling outside the artifact.
