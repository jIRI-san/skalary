# Decision: review concern taxonomy and ledger mapping

## Concerns

Both `cr` and `dr` use the same seven concern ids, so a finding class means the same thing whether it came from a plan review or a code review.

| Concern id | Lens |
|---|---|
| `security` | OWASP Top 10, trust boundaries, injection, secrets, path confinement, authz |
| `correctness-reliability` | logic errors, error handling, retries/timeouts, race conditions, corner cases, fail-loud behaviour |
| `architecture-patterns` | design-note conformance, architecture-contract violations, abstraction fit, composition vs inheritance |
| `performance` | allocations, hot-path I/O, N+1, unbounded growth, latency/throughput targets |
| `testing-evidence` | coverage gaps, weak or missing typed evidence markers, fixture quality, flaky patterns |
| `maintainability-consistency` | naming drift, duplication, dead code, commented-out code, style deviation, docs sync |
| `operability-observability` | structured logging, metrics, diagnosability, audit/receipt visibility, rollback clarity |

Every concern agent additionally checks the architecture-notes tier for contracts its lens touches; a `locked` contract violation is a finding regardless of which concern surfaced it.

## Concern → review-ledger category map

The map is **total and deterministic** but not bijective — two concerns can land in one ledger category. This removes the judgment call from `/ci` harvest, which currently distils ledger entries by rubric keywords.

| Concern | `cr` ledger category | `dr` ledger category |
|---|---|---|
| `security` | `security.md` | `security.md` |
| `correctness-reliability` | `error-handling.md` | `error-handling.md` |
| `architecture-patterns` | `consistency.md` | `consistency.md` |
| `performance` | `performance.md` | `performance.md` |
| `testing-evidence` | `testing.md` | `plan-structure.md` |
| `maintainability-consistency` | `consistency.md` | `consistency.md` |
| `operability-observability` | `observability.md` | `observability.md` |

`testing-evidence` is the only concern whose target differs by review type: in a plan review, evidence findings are about phase gating and marker coverage (`plan-structure`), while in a code review they are about test quality (`testing`).

`ledger-consult` (the read side) keeps its existing keyword rubric — the map governs the **write** side only, so consulting stays cheap and targeted.
