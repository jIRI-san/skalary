# Domain Model

## Terms and meanings

- **Canonical source** — `plugins/<name>/` plus its `plugin.json`; generators derive bundled scripts,
  registry, marketplace, and dogfood output from it.
- **Consumer repository** — the target Git repository whose `.github/` tree receives installed plugin
  payload and minimal receipts.
- **Minimal version receipt** — `.github/.skalary/receipts/<name>.json` with exactly `name`, `version`,
  `sourceIdentity`, and immutable `ref`. It records installed identity/version, not file ownership,
  integrity evidence, recovery state, or evaluation results.
- **Receipt-owned plugin** — a requested plugin whose valid minimal receipt has the same name and source
  identity. An explicit update may replace its old and new manifest-owned paths.
- **Manifest-owned path** — a `.github`-relative destination declared by the plugin manifest at a resolved
  immutable ref. Ownership is derived when needed from that source, not stored per file.
- **Published retirement metadata** — the active registry's retired-name and pinned-manifest records,
  generated from `registry-retirements.json`; it refuses reinstall and supports explicit removal.

## Actors and boundaries

- **Trusted operator** invokes direct plugin-manager scripts and approves mutating commands.
- **Source repository/ref** supplies immutable manifests and payload bytes for install, update, removal,
  and retired-plugin cleanup.
- **Consumer repository** owns all mutable installed files and receipts. Lifecycle code writes nowhere
  outside its `.github/` tree and never writes `.github/workflows/**`.
- **External consumers** depend on `plugin.json`, `registry.json`, and marketplace JSON. Their fields
  remain compatibility boundaries; lifecycle-internal state does not.

## Invariants

- Before any lifecycle read or write, the destination and every existing parent are physically
  canonicalized and rejected if rooted, traversing, linked, reparsed, outside `.github`, or below
  `.github/workflows`.
- Install/update/remove never claim success until the expected filesystem result is verified directly.
- Payload mutation precedes receipt mutation. A failed install has no new receipt, a failed update keeps
  the old receipt, and a failed removal keeps the receipt.
- An unchanged install/update/remove retry converges without new changes.
- A minimal receipt is the sole installed/version detector; it is not file-level deletion authority.
- Unforced remove compares present targets with the exact payload at the receipt ref and refuses the
  complete operation before deletion when any differ. `-Force` is the explicit exception.
- A matching minimal receipt authorizes explicit update replacement of old and new manifest-owned paths;
  local edits in those paths are not preserved.
- Retired plugins are never changed as a side effect of an unrelated install/update.
- No mutation lock, transaction journal, backup, rollback, recovery, CAS, preview, cursor, replay, or
  compatibility adapter is part of the lifecycle.
