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
