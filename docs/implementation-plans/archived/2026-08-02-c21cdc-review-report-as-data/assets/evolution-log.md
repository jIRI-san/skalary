# Design-review evolution

## Round 1

**Issues found:** 42 findings: 23 Critical around pre-dispatch truth, caller-selected policy/paths, artifact lifecycle, exact exits, bounded-output consistency, schema distribution, injection, state-machine completeness, test discovery, migration ordering, publication atomicity, and encoding; 8 High around native schema feasibility, cost/parity/versioning/rollback/digests/coverage; 8 Medium around duplicated gates, authoring, ownership, chat delivery, dependency proof, measured reduction, and timeout sizing; 3 Low around exit consumers, version bumps, and evolution-log indexing.

**Issues fixed:** added immutable pre-dispatch `Freeze`; fixed schema/path resolution to installed/computed locations; selected native `Test-Json` after a draft-2020-12 capability probe; separated structural capacity from byte-budget admission; selected manifest-last publication with lock/digest reader and injectable module boundary; made encoding, state, exits, diagnostics, artifact homes/lifecycle, and v1/v2 policy exact; added `8a0644 -> c21cdc`; reordered migration to keep the old API until both installed callers move; added golden parity, positive capability, discovery, cost, approval, consumer, and representative-size evidence; made bundle sync the schema writer; added durable indexed documentation and forward-repair rollback.

**Deferred/residual:** model compliance beyond installed instruction/eval contracts remains non-mechanical; same-user path replacement after validation remains a documented local TOCTOU residual mitigated by computed low-privilege roots, reparse checks, same-directory publication, and handles where available. Distinct formatter exits remain for diagnostics while callers classify them as clean/degraded/failure.

## Round 2

**Issues found:** 26 findings: 6 Critical on fixed input handshakes, retry transitions, PowerShell floor evidence, layout resolution, sidecar ownership, and terminal bounds; 10 High on approvals, cleanup, exit handling, root anchoring, secret retention, independence evidence, test/eval discovery, and manifest schema; 9 Medium on stale guidance, mutation/path/lock/performance/baseline evidence, graph assertions, phase size, and field encoding; 1 Low on duplicated status indexes.

**Issues fixed:** named fixed atomic input files and full replay/retry state machine; set and CI-probed PowerShell 7.6 floor; added `ReviewRuns` logical asset kind; specified schema sidecars as an extension of existing literal closure scanning with no new manifest field; fixed terminal/task byte limits and manifest/terminal schemas; derived repo root from installed script; added exact caller exit matrix, independent-dispatch evidence, secret redaction/guard, exact CR/DR eval ID sets, lock semantics, frozen mutation and confined manifest names; pinned performance and 44-finding methods; replaced permanent live-block assertion with edge/state equivalence; split Phase 2 to six points; named every stale document/index update.

**Deferred/residual:** none beyond Round 1 residuals. Existing platform suite ceilings remain the focused-consumer budget; no second ad hoc budget was added.

## Round 3

**Issues found:** 14 findings: 11 Critical on safe input authoring, repeated work, evidence drift, approval persistence, interrupted runs, verifying reads, reproducible performance, layout docs, parity, secret rejection, and PowerShell delivery; 3 High on admission correction, red phase sequencing, and structural-versus-runtime evidence.

**Issues fixed:** added editor `edit` as a two-temp-file-only review-agent boundary; changed lifecycle to Freeze once and Publish once; corrected test IDs and repartitioned to green checkpoints; assigned exact approval add/remove support to `Set-ScriptApproval`; chose bounded orphan abandonment as cancelled rather than resume; added verifying reader and generic cleanup scripts; made maximum-envelope execution mandatory on all CI legs; added plan-workflow/template ownership; replaced vague byte parity with closed semantic projection plus separate render goldens; destroy/redact secret-rejected input with a versioned corpus; kept wrapper at `#requires 7.0` with explicit 7.6 prerequisite status; made exit 3 terminal/new narrower run; separated structural evidence from the final live review artifact.

**Known Plan Issues:** none. Round 1's same-user local TOCTOU residual and non-mechanical model compliance remain explicit accepted limitations, not unresolved implementation choices.