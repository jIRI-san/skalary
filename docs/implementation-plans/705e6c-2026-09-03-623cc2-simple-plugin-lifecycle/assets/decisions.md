# Decisions

- **Optimize for one trusted operator.** Remove coordination and recovery mechanisms for hypothetical
  concurrent writers; retain concrete path and destructive-action safeguards.
- **Keep minimal installed-version receipts.** The operator revised the preliminary external-JSON-only
  rule: one per-plugin JSON receipt with exactly `name`, `version`, `sourceIdentity`, and immutable `ref`
  remains because it detects installed versions without a shared lockfile. Direct shape checks replace
  the receipt schema.
- **Receipt-last ordering replaces transactions.** Payload changes are verified first; install/update
  writes the receipt last and removal deletes it last. Failures remain visible and retry converges
  without rollback, journals, backups, repair, CAS, or a mutation lock.
- **Physical confinement is unconditional for lifecycle access.** Condition: a lifecycle command reads
  or writes a consumer path. Behavior: canonicalize the target and every existing parent and refuse
  traversal, rooted/drive/UNC/ADS forms, links/reparse points, outside-`.github` destinations, and
  `.github/workflows/**`. Exception: none.
- **Install refuses unowned collisions.** A path without a matching plugin/source receipt is not
  overwrite authority; only an explicit `-Force` invocation may replace it.
- **Explicit update replaces receipt-owned paths.** A matching plugin/source receipt authorizes the
  operator-requested update to overwrite local edits and remove obsolete old-manifest paths. This is the
  accepted consequence of dropping per-file hashes and degraded state.
- **Unforced removal is all-or-nothing.** Resolve the exact installed manifest from the receipt ref and
  preflight every present target. If any differs, perform no deletion and require `-Force`; missing paths
  are already converged.
- **Retirement is refusal plus explicit cleanup.** Keep `registry-retirements.json` as the direct source
  for published retired-name/pinned-manifest metadata. Install/update refuse retired targets; only
  explicit remove mutates an installed retired plugin. Delete preview/apply/cursor/replay/result state.
- **Keep external catalog contracts and existing generators.** Preserve externally consumed
  `plugin.json`, registry, and marketplace shapes; regenerate bundles, catalogs, and dogfood through the
  existing sequence.
- **Keep only valuable focused tests.** Retain current behavior, external-format, and high-impact
  confinement cases under the 30/60-second focused command contract. Delete transaction/recovery/state
  matrices and avoid routine broad or premium runs.
- **No legacy compatibility.** Existing broad receipts and retirement state get no migration or dual
  reader. A legacy receipt fails with an actionable diagnostic.
- **Execution uses container autopilot with no new packages.** Deterministic evidence is the normal
  judge; one risk-selected final CR is sufficient unless corrective changes invalidate it.
- **Rejected:** shared lockfiles, file ownership hashes/outcomes, degraded receipts, signing receipts,
  journals, backups, rollback transactions, CAS, repair/recovery, automatic retirement, hosted CI,
  internal lifecycle schemas, and replacement policy machinery.
