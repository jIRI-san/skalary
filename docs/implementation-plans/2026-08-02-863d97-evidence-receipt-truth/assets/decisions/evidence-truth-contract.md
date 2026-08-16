# Evidence truth contract

## Boundary

Execution producers determine what happened. The shared normalizer validates and canonicalizes that result. `Build-EvidenceReceipt.ps1` formats normalized results and exact policy; it never executes evidence. `Test-EvidenceReceipt.ps1`, hosted by `Test-Plan -Stage PlanCrosscheck`, pure-parses the persisted artifact, re-derives required marker coverage, freshness, policy approval, and disposition, and decides whether finalization may proceed.

`/cip` drafts and validates marker declarations. `/ci` and autopilot execute markers and publish receipts through the same installed contract. Review-run attendance and corroboration remain separate artifacts owned by `c21cdc` and `ca8ba8`.

## Status, findings, and disposition

Execution status is closed and immutable after normalization:

| Status | Meaning |
|---|---|
| `passed` | Every selected check executed and passed. |
| `failed` | At least one selected check executed and failed. |
| `skipped` | Every selected check was discovered but skipped. |
| `degraded` | Some selected checks passed and some skipped. |
| `unrun` | The marker was declared but execution was not completed. |

Typed findings are separate from execution status: `missing` (target absent), `stale` (digest mismatch), `malformed` (contract violation), and `error` (framework/discovery/timeout/load/internal fault). This avoids claiming an execution outcome for a parser or admission failure. A finding always blocks except where the existing architecture maturity contract derives advisory.

Gate disposition is derived separately after `cda9da` retires `arch:`:

- `passed` with no finding -> `satisfied`.
- `skipped` or pass/skip `degraded` plus one exact valid policy entry -> `waived`.
- Every other combination -> `blocked`.

A waiver never changes status and never renders as passed. The persisted line uses `U+2298` for waived, `U+2713` for satisfied, and `U+2717` for blocked.

## Focused Pester aggregation

Tracked `.github/evidence-test-scope.json` is a managed continue-implementation payload and the sole schema-validated owner of fixed repo-confined roots/patterns. Installation and update own it; there is no first-use scaffold. Autopilot declares the continue-implementation manifest dependency and invokes the allowlisted installed CI path, with no duplicate executor. Full-suite host exclusions are distinct from evidence discoverability, so a separately hosted test may still satisfy a marker. Roots cannot escape/reparse, generated profile/coverage scope is snapshot-only, and the independent coverage/removal baseline cannot regenerate during narrowing.

`Run-UnitTests.ps1` accepts a bound focused array of no-space test IDs. In one killable child invocation it discovers once, maps each ID to the exact leading token of every Pester name, runs all selected cases, and applies this precedence:

1. Framework, load, timeout, internal failure, `NotRun`, `Inconclusive`, interruption, or selected/executed count mismatch -> `error` finding and blocked disposition.
2. Any failed selected case -> `failed`.
3. Passed plus skipped selected cases -> `degraded`.
4. All selected cases skipped -> `skipped`.
5. All selected cases passed -> `passed`.
6. No exact leading-token match -> `missing` finding and blocked disposition.

The default timeout is 5 minutes and configured maximum is 10. Effective timeout is the lesser of requested and remaining hard budget, but a run starts only with at least 5 seconds; otherwise it returns distinct budget-exhausted exit `11`. Timeout exit is `9`, malformed/count is `10`. Existing suite `0-8`, parser `20-22`, and autopilot `42-43` remain collision-free. Timeout kills the process tree and discards partial results while preserving bounded selected/completed/in-flight attribution. The ordinary suite loads active non-archived strict plan inventories/policies once; exact owned waivers may authorize a skip, while archived or unowned IDs fail closed.

## Waiver authority

The optional policy is a layout-resolved plan asset (`assets/evidence-policy.json`, or `evidence-policy.json` for legacy layout). Each closed-schema entry binds stable waiver ID, canonical plan ID, exact requirement, exact marker, exact OS, one allowed status (`skipped` or `degraded`), and a non-empty bounded reason. Wildcards, duplicate bindings, extra fields, reparses, escapes, wrong-plan entries, delimiter/control injection, and caller-supplied dispositions are rejected.

`EvidencePolicy.psm1` is the sole policy/inventory/digest host. Root-only `Approve-EvidencePolicy.ps1` imports it, excludes approval from its own active-set digest, and records/revokes approval in the policy plus a matching bounded capture audit. It is never bundled, requires an attached nonredirected console and current `@human` finalization handoff, and exposes no force/env bypass. Parser requires the matching audit digest, making deletion/mutation blocking. Any policy/inventory change invalidates approval. Absent policy is canonical empty and requires no approval. Human PR review remains the residual authorship trust anchor.

## Receipt freshness and lifecycle

The strict v2 prologue carries UUID, optional predecessor/reason, `scope=phase|final`, phase/inventory, source commit, state, projection digest, inventory/policy/approval digests, bound review/audit/CI-proof digests, class subdigests, and selected/completed/in-flight counts. `EvidenceDigest.psm1` inspects Git index modes, rejects gitlinks/non-blobs/symlinks, and hashes every tracked file through a canonical projection that normalizes only stage/check/archive lifecycle fields in mixed-content `plan.md`; it excludes receipt and generated CI-row bytes but binds their independently verified compact proof digests. Limits are 20,000 files, 8 MiB/file, 64 MiB total, and 30 seconds. The parser reports changed classes from its own recomputation.

Publication holds a stable per-plan exclusive lock with 5-second timeout and rereads state under lock. Start atomically writes blocked running state. Terminal CAS requires the same UUID, scope, immutable running digest tuple, and complete scope inventory; any input change abandons/restarts. A later run carries predecessor UUID/reason and never resumes. Phase terminal receipts prove only their phase and cannot authorize PlanCrosscheck; only final scope covers all markers. A crash or stale terminal writer leaves/returns blocked state.

V2 is introduced dormant: APIs and tests first, all callers second, then one atomic authority switch in `Test-Plan` with v1 removal. There is no interval where both formats can authorize completion.

## Compatibility and simplicity

Legacy result objects remain accepted only when `Status` is absent: `Success=true` maps to passed, `false` to failed, and `null` to unrun. A result carrying both fields must agree or becomes malformed. There is no legacy waiver adapter. Strict `evidence: required` plans must rebuild a v1/old-grammar receipt at their next crosscheck; plans outside that opt-in remain warn-only.

The receipt stays a deterministic line artifact. Admission is capped at 128 markers, 32 waivers, 256 cases/marker, 1024 total cases, 64 diagnostics, and 256 KiB. Discovery/policy maps are ephemeral. Raw text is untrusted and never enters instructions/commands; agents consume only the closed verdict. Final ordering is CR/fixes, policy approval if nonempty, authenticated same-source-commit CI proof, final receipt, PlanCrosscheck; any non-lifecycle mutation restarts the loop.