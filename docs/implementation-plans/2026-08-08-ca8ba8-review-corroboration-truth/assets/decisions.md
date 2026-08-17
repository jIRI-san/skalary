# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Measure output similarity, not claimed serving identity.** A model cannot attest its own runtime identity, but suspiciously similar outputs are observable.
- **Suspicion can only lower confidence.** Near-identical nominally independent findings are flagged and excluded from corroboration or severity elevation.
- **State observable corroboration without overclaiming.** Reports say “corroborated, no suspicious similarity observed” and expose support, similarity, attendance, and elevation as separate dimensions; they never claim served-model independence.
- **Preserve independent discovery.** Rejected: feed model A's findings to model B; it destroys unanchored agreement and serializes the fanout.
- **Keep v1 ownership with `c21cdc`.** This plan never mutates v1 semantics or historical authority in place. Readers remain dual-version; all new CR/DR publication uses an explicit v2 authority.
- **Separate raw input from derived authority.** Callers submit closed `skalary/review-result@1` data with no aggregate corroboration fields. The engine derives and publishes `skalary/review-run@2` plus `skalary/review-manifest@2`, so a caller cannot spoof corroboration.
- **Use the simplest deterministic near-duplicate policy.** Compare canonical title/body/action payloads within a merge group across declared models: normalized exact equality always flags; otherwise 3-token-shingle Jaccard at 9000 basis points flags only when both payloads have at least 12 tokens. No embedding model, network call, package, or configurable threshold.
- **Require clean unanimous unsuspicious support for elevation.** A group rises one level only when all tasks completed and every roster model retains support not involved in a suspicious pair. Suspicion preserves visibility and raw severity but never raises confidence.
- **Keep review completion separate from corroboration quality.** Suspicion adds no process exit. Completed execution remains exit 0; existing attendance degradation remains exit 5.
- **Run container-autopilot for the whole plan.** All work is repository-local, has no human-only action or external side effect, and adds no third-party package.
- **Bound evidence with deterministic witnesses, not truncation.** V2 stores the total suspicious-pair count and digest plus one ordinal-first witness per affected finding. The manifest-bound raw authority permits full recomputation; truncation is never a hidden confidence increase.
- **Frame every digest input.** Group, finding, and pair digests use ordinal-sorted UTF-8 length-prefixed tuples. Untrusted model labels or field boundaries cannot forge a composite key.
- **Use a frozen-v1 completion bridge.** New freezes bind plan@2 and policy@1 and publish v2. A run already frozen under plan@1 can only complete/replay v1. The caller never chooses the production version.
- **Make admission partitions merge-group atomic.** A child owns whole groups and the parent verifies exact group coverage. One group that cannot fit fails exit 3 rather than producing partial corroboration.
- **Retain compact corroboration commitments.** The versioned final report/receipt pair survives cleanup with policy/group digests, dimensions, elevation reasons, and witnesses; live authority remains transient.
- **Stage readers before writers.** Dual readers and the v1 completion bridge land first. Writer rollback leaves v2 readers installed; published v2 authority is never downgraded.
- **Reject runtime timing in canonical authority.** Persist deterministic pair counts for diagnosis, but keep wall-clock and allocation measurements in test evidence so canonical bytes remain reproducible.
- **Keep both architecture contracts active by scope.** `ARCH-Review-Run-V1` governs v1 authority; draft `ARCH-Review-Run-V2` governs new freezes/publication and references the versioned policy descriptor. The index and generated human document name both.
- **Make unpartitionable admission permanent per run id.** A single group that cannot fit writes terminal admission@2 with bounded reason and required counts/bytes. Identical replay returns exit 3; changed input remains an immutable-run conflict at exit 2.
- **Do not create pending v2 freezes during reader rollout.** The reader-first phase changes no writer behavior. Activation switches new freeze and publish to v2 together; every frozen run completes under its bound version and policy, including after rollback.
- **Separate raw, effective, and approval truth.** Retained evidence stores raw maximum and post-policy effective severity. Suspicion forces `needs-review`; confidence suppression can never become approval.
- **Keep retained evidence within 8 KiB through aggregate commitments.** Preserve policy and overall group-set digests, aggregate dimensions/counts/verdict, and bounded witnesses. Per-group rows are all-or-nothing and omitted when they do not fit.
- **Name raw input and authority roles explicitly.** The caller writes `review-result.input.json`; the engine commits `review-result.<sha256>.json`; manifest@2 binds closed `rawResult` and derived `canonical` roles with separate budgets.
- **Use 16,384 as the reachable candidate ceiling.** Under the supported two-model roster and 256-finding maximum, the largest cross-model product is `128 * 128`; the descriptor test derives this value from shared limits.
- **Test the future-proof count guard directly.** A valid policy@1 envelope reaches 16,384 but cannot reach 16,385. The one-above case targets the pure candidate-limit function with a synthetic count; envelope tests cover the reachable maximum.
- **Limit policy@1 to exactly two declared models.** This matches current dispatch and makes the ceiling meaningful. Three-model behavior is not promised by policy@1; broader rosters require a versioned policy change.
- **Use deterministic ASCII token semantics.** After invariant folding and format-control separation, tokens are `[a-z0-9]+`. This avoids runtime Unicode-table drift at the accepted cost of disclosed non-ASCII false negatives.
- **Add explicit receipt and terminal-status v2 contracts.** Receipt@2 owns raw/effective severity, verdict, commitments, and bounded diagnosis. Status@2 exposes `needs-review` to headless callers while successful completed execution remains exit 0.
- **Keep witnesses derived-only.** Witnesses contain identifiers, declared labels, score, and payload digests, never reviewer-authored text. Their trust class is engine-derived metadata.
- **Pin policy authenticity, not only shape.** The engine version map carries each supported descriptor SHA-256; freeze and frozen-run completion fail exit 2 if exact policy bytes are unavailable.
- **Apply performance limits to the aggregate parent operation.** The existing platform time/private-byte ceiling covers all child similarity passes and rollup together, not each child independently.
- **Give v2 limits a separate owner.** Immutable v1 limits and embedded copies stay untouched. V2 schemas embed definitions deep-equal to `review-v2-limits.schema.json`; version dispatch owns shared lifecycle precedence.

## Prior-art reconciliation

- **Reuse `c21cdc` REQ-1/6/9/10, RISK-6, and D1/D2/D9/D10/D13/D14/D28.** Preserve frozen scope, manifest-last immutable authority, declared-model precision, lifecycle, artifact homes, and compact retained evidence.
- **Extend `c21cdc` RISK-7.** Replace declared-label unanimity with observable, bounded similarity evidence and a truthful elevation rule in v2.
- **Resolve `c21cdc` RISK-10 by versioned ownership.** `c21cdc` remains the complete v1 owner; this plan adds v2 and dual-version readers rather than independently rewriting attendance or persistence.
- **Reuse `863d97` decision “Keep review attendance separate.”** Marker/receipt truth remains outside review attendance and corroboration authority.
- **Reuse `34088e` REQ-6.** New contract descriptors remain owner-local, discoverable, and explicitly versioned.
- **Reuse `583308` typed-evidence decision.** Ordinary Pester remains the `test:` evidence host; workflow/review observations are not mislabeled as typed tests.

## Similarity policy details

- Normalize each `title`, `body`, and `action` independently using NFC/LF canonicalization, invariant folding, direction/format controls mapped to separators, and collapsed whitespace. Rendering displays direction controls as visible `U+XXXX` escapes.
- Exact comparison uses a UTF-8 byte-length-prefixed tuple of the three normalized fields.
- Approximate comparison tokenizes ASCII `[a-z0-9]+` within each field. Three-token shingles carry the field id, so no shingle crosses a field boundary.
- Compute Jaccard in integer basis points with 64-bit arithmetic. A score of 9000 is suspicious; 8999 is not. Empty unions and payloads below 12 total tokens are exact-only.
- Precompute each finding's tuple, token count, and shingle set once. Compare only cross-declared-model candidates inside a merge group, after the candidate count passes the 16,384 policy ceiling.
