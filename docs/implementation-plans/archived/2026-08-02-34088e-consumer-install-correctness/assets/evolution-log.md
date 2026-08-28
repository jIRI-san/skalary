# Design Review Evolution

## Round 1 — 2026-08-15

**Issues found:** 104 findings. One unsupported prompt-injection claim was retained in the published review artifact and rejected. The remaining findings clustered around retirement sequencing, fixture ownership, probe attendance/isolation, scanner migration, filesystem races, limit ownership, folder-stable dependency evidence, runtime budgets, diagnostics, and authoritative platform attestations.

**Issues fixed:** Added hard `34088e -> cda9da` and `8a0644 -> 34088e` decisions; narrowed retirement to consumer transition deltas; selected the production installer and one shared fixture substrate; defined schema-backed one-process-per-plugin probes, exact attendance, zero skips, canaries, deadlines, and bounded reports; staged scanner enumerate/disposition/enforce; selected parent-identity mutation rechecks; named owner-local limit descriptors and compatibility; replaced folder evidence with resolver-backed graph tests; added early 10s/30s/60s runtime allocations and a blocking integration-tier fallback; required current-tree Linux/Windows CI attestations.

**Operator decisions:** Hard retirement and fleet dependencies; fresh CI receipts for both platforms; parent identity recheck rather than native handle-relative no-follow; blocking integration tier rather than reduced coverage or a ceiling raise.

**Deferred residual:** Handle-relative no-follow mutation primitives remain outside this plan after reparse-ancestor rejection and immediate parent-identity verification.

## Round 2 — reconciled from round-3 frozen scope

**Authority note:** No separate round-2 review bundle is retained. The round-3 frozen scope records the accepted round-2 outcomes; this entry preserves that provenance without inventing a finding count.

**Issues fixed:** Added CI receipt/evidence producers, absolute ordinary/tier runtime contracts, aggregate deadlines and network isolation, production source guards, bundle closure, typed scanner inventory, incumbent gate widening, manifest probe descriptors with recoverable attendance, `cda9da` ownership/mapping, ordered limit discovery, resolver-backed `8a0644` evidence, epic narrative, and a final budget rerun.

## Round 3 — 2026-08-21

**Issues found:** 18 merged findings: 4 Critical, 3 High, and 11 Medium. They covered probe concurrency/deadlines, atomic gate inventory updates, credential isolation, scanner-state lifetime, candidate/evidence identity, scaffold bindings, descriptor confinement, shared-surface sequencing, measurement producers, cleanup confinement, scanner cost/caps, retirement scope, copied-limit detection, network-state recovery, platform measurement ordering, capability outcomes, and review-limit ownership.

**Issues fixed:** Added machine-owned scanner/probe policies and exact caps; deterministic four-process waves with tier-bound aggregate terminal handling; allowlisted child environments and isolated profiles; manifest-first network-state reclaim; scanner-owned persistent exclusions; confined direct probe/scaffold bindings; in-place atomic `gate:review-consumer-install` updates; serialized registry mutation; validation-host scanner timing; candidate-parent evidence semantics; narrowed retirement delta proof; bounded copied-literal discovery; typed blocking capability outcomes; and non-validating review-budget ownership.

**Simplicity gate:** Reused the existing validation host, production installer, manifest/Test-Registry confinement, CI gate row, review limits schema, and upstream retirement tests. Rejected a second installer, a second CI host, a global limits catalog, shell-based probe execution, and duplicated retirement fault tests.

**Deferred residual:** The round-1 handle-relative no-follow residual remains unchanged. No round-3 finding is deferred.