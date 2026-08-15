## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] Canonicalization unrolled arrays and empty containers, allowing digest-preserving shape mutations.
- [1.1] [src:code-review] [sev:Med] Fixture manifest did not require exact confined file-set equality.
- [1.1] [src:code-review] [sev:Med] Historical manifest formatted but did not verify its starting Git commit blobs.
- [1.1] [src:code-review] [sev:Med] Historical rehash followed symlink or reparse paths outside the repository.
- [1.1] [src:code-review] [sev:Low] Rubber-duck found no blocking defect; moved mutation proof into an isolated temporary Git repository to avoid interrupted-run worktree damage.
- [1.2] [src:code-review] [sev:Med] Marker parser truncated backtick-delimited file contains assertions containing spaces.
- [1.2] [src:code-review] [sev:Med] Review marker prefix matching accepted review critical and review drift as valid review evidence.
- [1.2] [src:code-review] [sev:Med] Unknown-prefix detection omitted unquoted retired arch markers after prose.
- [1.2] [src:code-review] [sev:Med] Architecture-tests review report still called the removed plan evidence evaluator.
- [1.2] [src:code-review] [sev:High] Rubber-duck found the architecture-tests-local review helper nested inside config resolution and unavailable on real report calls.
- [1.3] [src:code-review] [sev:Low] Code-review and rubber-duck found no actionable defect in the retirement catalog or history gate.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Retirement-state paths required link/reparse rejection in addition to lexical .github confinement; fixed before every read/write.
- [2.1] [src:code-review] [sev:Med] Source identity version validation coerced non-integer values to version 1; fixed with exact integer-type validation.
- [2.1] [src:code-review] [sev:Med] Receipt schema allowed SHA-1 refs only while runtime accepts SHA-256 object IDs; fixed to allow 40 or 64 hex.
- [2.1] [src:code-review] [sev:Med] Marketplace metadata lagged the generated plugin-manager version bump; regenerated marketplace.
- [2.1] [src:note] [sev:Low] Rubber-duck second opinion found no high-confidence defects after review fixes.
- [2.1] [src:code-review] [sev:Med] Canonical identity validation used case-insensitive PowerShell comparisons; fixed to reject non-canonical kind and identity casing.
- [2.1] [src:code-review] [sev:Med] GitHub URI parsing accepted arbitrary schemes and rejected explicit standard SSH ports; fixed with a closed transport/port allowlist.
- [2.2] [src:code-review] [sev:High] Non-force removal could delete update-owned skipped-modified files whose receipt hash matched current content; fixed to require force for that outcome.
- [2.2] [src:code-review] [sev:High] Untrusted journals did not bind restored destinations to receipt pre-state ownership; fixed with exact ordinal destination/hash and post-state transition validation.
- [2.2] [src:code-review] [sev:High] Journal and receipt JSON rewrites were not crash-atomic; fixed with flushed same-directory temporary files and atomic replacement.
- [2.2] [src:code-review] [sev:High] Install/update and the explicit dependent check did not share the removal mutation lock; fixed by locking all plugin mutators.
- [2.2] [src:code-review] [sev:Med] Retirement intersection used case-insensitive hashtables; fixed with ordinal dictionaries and a case-mismatch zero-mutation test.
- [2.2] [src:code-review] [sev:High] Recovery scoped journals by source but not expected immutable ref/version before mutation; fixed with pre-restore scope validation.
- [2.2] [src:code-review] [sev:High] Missing-receipt recovery could accept a null post-state journal covering only part of receipt ownership; fixed to require full pre-state coverage.
- [2.2] [src:code-review] [sev:Med] Recovery evidence was deleted before fallible directory pruning; fixed by retaining journal/backups until cleanup succeeds.
- [2.2] [src:note] [sev:Low] Rubber-duck found no blocking defects; fixed pre-journal temp residue and added embedded/published journal-schema drift proof.
- [2.3] [src:code-review] [sev:Med] Terminal residue with a degraded receipt was re-entering preview/apply; fixed by handling terminal states before receipt matching with metadata-only replay.
- [2.3] [src:code-review] [sev:Med] A hard kill after committed removal could strand state as applying without journal/receipt; fixed with verified applying-state terminal recovery.
- [2.3] [src:code-review] [sev:Med] The 64-path cap truncated output after statting all paths and had no per-state fairness; fixed with bounded circular replay cursors persisted per state.
- [2.3] [src:code-review] [sev:Med] Manual-required residue was not persisted or replayed; fixed with schema-valid manual metadata states and bounded terminal reporting.
- [2.3] [src:note] [sev:Low] Rubber-duck found no blocking defects; added explicit success exits for authoritative bootstrap propagation and parenthesized cursor type validation.

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:Med] Regenerated suite profile prematurely reset Phase 3 baseline/target and recorded a failing run; defer the Phase 3 profile receipt to step 3.2.
- [3.1] [src:code-review] [sev:Low] Rubber-duck: preserve the architecture-notes negative assertion against reintroducing the retired architecture-tests reference; guard restored.
- [3.2] [src:code-review] [sev:Med] Copilot CLI manual residue was treated as a repo-relative literal and replay assertions covered only the approval path; added confined user-home observation plus all-category repeated non-mutation proof.
