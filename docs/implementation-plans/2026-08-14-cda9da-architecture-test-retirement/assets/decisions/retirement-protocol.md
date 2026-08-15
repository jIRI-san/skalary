# Plugin Retirement Protocol

## Authority

`registry-retirements.json` is the canonical, permanent list of retired plugin names. `schemas/registry/plugin-retirement.schema.json` validates it; `Build-Registry.ps1` emits deterministic `retiredPlugins` records into skalary's registry only; and `Test-Registry.ps1` rejects active/retired overlap and name reuse without reading Git. A separate pure-file comparator receives one explicit baseline blob and the candidate, performing $O(T)$ changed/removed-record checks; PR/push CI owns materializing the base-branch or previous-main blob and fails when required baseline materialization is unavailable. The initial `architecture-tests` record is pinned by an exact negative fixture. Absence alone cannot authorize deletion.

Each tombstone contains immutable known payload sets keyed by normalized source identity, ref, and version. Every set carries exact destination/SHA256 pairs; the current receipt may narrow this set but can never add deletion targets. Legacy/unknown payload sets produce `manual-required`. Tombstones also retain `manualResidue` metadata for manifest scaffolds outside `.github`, Copilot CLI installs, and approval keys; these records are discovery authority only and never authorize automatic mutation.

One versioned helper returns credential-free source identity for every install/update/receipt/retirement caller. GitHub remotes persist normalized host plus owner/repository without userinfo, query, fragment, or token; local sources persist a canonical-path digest rather than the path; immutable ref stays separate. Legacy source labels are upgraded only when unambiguous. A foreign source is a no-match; an ambiguous matching legacy receipt blocks with a migration remedy. Sentinel secrets are forbidden from state, success output, warnings, errors, and logs.

## Transaction

Install and update call one shared reconciler after source and registry verification, before active-name lookup and every already-current/no-op return. It indexes tombstones, same-source receipts, and retirement states in $O(R+I)$ metadata work and hashes files only for a matching tombstone entering preview/apply. A residue state never rehashes on automatic replay.

The first capable operation writes only a schema-valid preview under a plugin-name-validated, confine-resolved `.github/.skalary/retirements/<name>.json`. Durable state includes the complete affected path/hash set, prior source/ref/version, transaction id, and remedy; only emitted output is capped, with total and omitted counts. No payload is deleted. A later capable operation applies automatically; `-ApplyRetirements` refuses missing, stale, source-mismatched, tombstone-mismatched, or receipt-mismatched preview with zero mutation and a dedicated remedy. Direct install/update of a retired target emits the same result then exits with a dedicated target-retired code instead of generic not-found.

When automatic reconciliation sees stale preview input, it replaces it with a newly derived zero-deletion `preview`; explicit `-ApplyRetirements` against stale input returns `failed` and the remediation needed to refresh first. Preview and journal contents never determine the apply set.

Apply routes through the same removal primitive as `Remove-Plugin`. Under the existing mutation lock it rederives the deletion set from the current same-source receipt plus current tombstone, never from preview or journal. Before any journal, backup, delete, or prune it rejects traversal/rooted paths and links/reparse points throughout destination and parent chains. The confined journal is untrusted input: schema, plugin/source identity, transaction ownership, pre-state, path confinement, backup hashes, and current receipt are verified before scoped recovery. Mixed-version pre-state mismatch fails closed. A recovered failed transaction can transition back to preview only after exact rollback/recovery verification. Success and rollback remove temporary state; deterministic seams cover every boundary and one hard-kill covers process termination.

Receipt-matching files are removed. If all files are clean, the receipt disappears, while the compact retirement state retains recovery metadata and terminal `retired` status. Modified files are never deleted automatically: the existing receipt remains `degraded` with `skipped-modified` ownership entries, while terminal `residue` state records expected and observed hashes at retirement time. Later automatic reconciliation is metadata-only. Non-force explicit removal preserves both authorities; only `Remove-Plugin -Force` through the shared primitive deletes residue and closes the state. Unrelated `Install-Plugin`/`Update-Plugin -Force` cannot authorize it.

Every invocation emits at most one bounded aggregate `RETIREMENT: <json>` success-stream record. Terminal replay processes at most 8 plugins and 64 re-confined paths per invocation through a persisted fair plugin cursor plus per-state path cursor, stats without hashing, repeats remedies while residue remains, and eventually visits every record. An `applying` state resumes from a validated journal; if removal committed before terminal state persistence, verified receipt/payload post-state closes it as `retired` or `residue`.

| Outcome | Mutates payload | Persists state | Unrelated operation | Exit | Remedy |
|---|---:|---:|---|---:|---|
| `no-match` | no | no | continue | 0 | none |
| `preview` | no | yes | continue | 0 | rerun or explicitly apply |
| `retired` | yes, pinned intersection only | yes | continue | 0 | pinned-ref restore if needed |
| `residue` | clean intersection only | yes | continue | 0 | explicit `Remove-Plugin -Force` |
| `foreign-source` | no | optional observation | continue | 0 | use owning catalog |
| `manual-required` | no automatic mutation | yes | continue | 0 | emitted scaffold/CLI/approval remedy |
| `recovered` | recovery only | yes | continue | 0 | rerun requested operation |
| `failed` | rolled back | yes | block | 21 | repair/reset then retry |

A direct request whose target is retired emits the applicable non-failed outcome record and exits 20 instead of continuing or returning generic not-found. `failed` remains 21. Bootstrap and every wrapper propagate 20/21 unchanged. No raw source, secret, unconstrained path, or per-path unbounded output is emitted.

## Lifecycle

Tombstones are permanent and reserve names against reuse. Fresh installs cannot select a retired plugin because it has no active catalog entry. Existing consumers begin convergence only after bootstrap or plugin-manager update installs a reconciliation-capable script; an old-installer fixture proves its first old-code operation does not falsely claim cleanup. The first capable operation previews, the next applies, including operations that would otherwise return already current.

Installer authority remains confined to `.github`; any old scaffold/config/receipt outside it is reported as human-owned residue with a precise manual path/remedy, never deleted. Reverting this repository cannot restore removed consumer files. Recovery uses the terminal state's prior immutable ref and an explicit pinned-source install; staying restored requires remaining pinned or operating without a current-source reconciliation call.