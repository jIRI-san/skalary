# Design Review Evolution Log

## Round 1 - 2026-08-16

- Run: `cd99eb8a-daa1-4112-a63c-afc1107959be`; 14/14 tasks completed; 28 merged findings from 85 raw records.
- Issues found: v2/version ownership gaps, unbounded or ambiguously framed similarity evidence, partition/replay/retained-evidence gaps, v1 projection risk, late distribution sync, weak phase evidence, and incomplete rollout/architecture policy.
- Issues fixed: selected bounded witnesses plus complete pair digest, UTF-8 length-prefixed framing, a schema-validated policy descriptor, frozen-v1 completion bridge, engine-owned version map/replay basis, merge-group-atomic partitioning, compact v2 retained evidence, reader-first activation, isolated v1/v2 projections, immutable v1 inventory, phase-local evidence, atomic sync, and explicit test tiers/resource cases.
- Issues deferred: lexical false negatives and malicious echo can suppress elevation; both are accepted fail-closed residual risks and are rendered without suppressing findings. Runtime timing is rejected from canonical authority; deterministic pair counts plus external budget tests provide diagnosis without breaking reproducibility.

## Round 2 - 2026-08-16

- Run: `1e88dd3d-7316-43be-8c25-30f3502107e6`; 14/14 tasks completed; 18 merged findings from 38 raw records.
- Issues found: admission permanence and versioning, unreachable pair ceiling, inconsistent staged freeze behavior, undefined final verdict, retained-evidence overflow, role naming/budgets, partition ownership/rollup, structured reads, documentation/sync timing, traceability, and aggregate cost.
- Issues fixed: selected permanent terminal admission@2, corrected the two-model ceiling to 16,384, kept reader-only rollout writer-neutral, bound frozen completion to version/policy, stored raw/effective severity with suspicion forcing `needs-review`, chose aggregate 8 KiB commitments, named fixed/addressed raw-result roles, added structured reads and role budgets, defined deterministic whole-group children/rollup, moved docs/sync into owner steps, aligned mappings, and added summary/retained/eval/16-child evidence.
- Issues deferred: none beyond the round-1 accepted lexical and hostile-echo residuals.

## Round 3 - 2026-08-16

- Run: `13a6dbb8-fb3c-4d4b-bc56-42bd78dbe4f1`; 14/14 tasks completed; 28 merged findings from 36 raw records.
- Issues found: unreachable envelope one-above case, missing terminal diagnostics, unbounded shingle work, early evidence closure, policy authenticity/retention, secret-write ordering, traceability drift, retained diagnosis/verdict/status gaps, ambiguous aggregate budget, receipt/schema naming/limits ownership, activation operations, direction controls, Unicode stability, shared primitive precedence, and cross-platform proof.
- Issues fixed: direct pure count-gate evidence, terminal group/role/bytes/limit/guidance, exactly-two-model ASCII policy with schema-derived shingle/memory bounds, descriptor digest pinning and retention, secret scan before raw writes, explicit receipt/status v2 and `needs-review` refusal, aggregate parent worker ceiling, canonical schema homes and v2 limits owner, version-map activation capability/runbook, visible direction-control handling, shared lifecycle/primitive precedence, derived-only witnesses, synchronized mappings/markers, and CI-owned two-platform receipts.
- Issues deferred: policy@1 intentionally has non-ASCII and semantic-paraphrase false negatives; malicious echo can force `needs-review` and suppress elevation. Both are accepted fail-closed residuals, not silent confidence increases.