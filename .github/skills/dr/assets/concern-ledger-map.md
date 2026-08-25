# Concern -> review-ledger category map

The map is **total** (every concern has a target for both review types) and **deterministic**, but
not bijective: two concerns can land in the same ledger category. Its job is to remove the judgment
call from `/ci` harvest, which otherwise distils ledger entries by rubric keywords.

| Concern | `cr` ledger category | `dr` ledger category |
|---|---|---|
| `security` | `security.md` | `security.md` |
| `correctness-reliability` | `error-handling.md` | `error-handling.md` |
| `architecture-patterns` | `consistency.md` | `consistency.md` |
| `performance` | `performance.md` | `performance.md` |
| `testing-evidence` | `testing.md` | `plan-structure.md` |
| `maintainability-consistency` | `consistency.md` | `consistency.md` |
| `operability-observability` | `observability.md` | `observability.md` |

`testing-evidence` is the only concern whose target differs by review type: in a plan review,
evidence findings are about phase gating and marker coverage (`plan-structure`), while in a code
review they are about test quality (`testing`).

## Usage

- **Write side (harvest):** a finding raised by concern `X` is appended to the category this table
  names for the review type that produced it. Pass that category to
  `scripts/skalary/Add-LedgerEntry.ps1 -Category <name>` with the file extension dropped. There is no
  fallback branch: an unmapped concern is a bug in this table, not a cue to improvise.
- **Read side (`ledger-consult`):** unchanged. Consulting keeps its existing keyword rubric so a
  lookup stays cheap and targeted; this map governs the **write** side only.
