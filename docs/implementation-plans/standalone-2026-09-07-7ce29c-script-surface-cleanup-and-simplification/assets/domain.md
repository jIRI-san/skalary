# Domain Model

## Terms and meanings

- **Active script surface** — canonical production scripts plus manifest-owned installed copies used by
  a current command, runtime, validation path, or documented operator workflow.
- **Dead wrapper** — a script with no active caller that only adapts another command or test.
- **Completed migration** — a one-shot transition whose target convention is now created directly and
  whose migration path is no longer a supported operator capability.
- **Historical snapshot fixture** — byte-pinned copies of a retired subsystem retained only to prove
  its former contents.
- **Compatibility view** — generated `architecture.human.md` and the generator, digest, freshness, and
  distribution machinery that keep it synchronized with legacy JSON contracts.
- **Semantic deletion** — removing duplicate, unreachable, superseded, or needless private control flow
  rather than compressing formatting or moving code to another file.
- **Public export** — a function named by `Export-ModuleMember`; this is the compatibility boundary for
  the three simplified modules.

## Actors and boundaries

- The single operator invokes supported scripts and skills from the repository or an installed plugin.
- Canonical root scripts own shared implementations; plugin manifests and sync tools own distribution
  copies.
- Pester suites provide deterministic current-behavior evidence. Historical implementation bytes are
  not runtime evidence.
- Architecture Markdown is the human-readable authority. The remaining JSON contract may still be
  validated directly, but no generated Markdown mirror remains.

## Interfaces and ownership

- `EpicAutopilot.psm1` exports only `Invoke-EpicAutopilotHostLoop`.
- `WorkHierarchy.psm1` retains its current 16 exported projection, mapping, dry-run, apply, and provider
  functions.
- `DirectWorkflow.psm1` retains its current seven exported criteria, review, standards, framing, and
  evidence functions.
- `Sync-PluginScripts.ps1`, registry/marketplace builders, and `Sync-Dogfood.ps1` remain the only writers
  of generated distribution state.
- `clean-sandbox-cache.ps1` remains an explicit manual maintenance command owned by the autopilot plugin.

## Invariants

- Public exports and documented user-visible behavior remain unchanged during module simplification.
- No new production module is introduced for code moved out of the three large modules.
- Current safety boundaries—path confinement, destructive-action approval, secret screening, and
  external-format validation—remain intact.
- Generated copies are changed through their owning manifests and generators, never as independent
  sources.
- Deleted historical or compatibility machinery does not gain a replacement ledger, schema, migration,
  or generalized framework.
