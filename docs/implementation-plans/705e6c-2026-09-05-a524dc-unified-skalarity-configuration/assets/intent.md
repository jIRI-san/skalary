# Intent

Preliminary context captured during epic refinement; `/cip` must confirm and refine it after its three
dependency children have established the final configuration surfaces.

## Goal

Provide one `/skalary-config` skill that helps a single operator discover, bootstrap, understand, and
change Skalary configuration across all installed plugins without learning each subsystem's file layout.

## Desired outcome

The operator opens one guided menu or names a category/command. The skill shows effective values,
source/default/precedence, examples, risks, effort, and complexity; proposes a complete diff; validates
before mutation; writes canonical sources only after one Apply/Cancel decision; then invokes existing
synchronization and focused validators. Direct subsystem configuration remains usable.

## Success signals

- Autopilot, models/reviews, local review standards, terminal approvals, evals, note scaffolds, and
  advanced plugin/toolchain policy are discoverable from one skill.
- Missing optional configuration is created only when the operator selects that surface.
- Every displayed value names its canonical source, default, precedence, generated copies, consumer,
  synchronizer, and focused validator.
- Apply writes no generated/dogfood copy directly and leaves no synchronization drift.
- Unknown fields and unrelated settings survive edit and per-key reset.
- Secrets are never displayed or persisted; only credential-source availability is shown.
- Runtime state, plans, receipts, schemas, retirement history, generated catalogs, and workflows are
  excluded or explicitly read-only.
- Focused tests cover discovery, precedence, bootstrap, diff-before-write, cancellation, apply,
  reset, source synchronization, secret refusal, executable-setting confirmation, and invalid models.

## Non-goals

- Replacing subsystem-owned configuration formats or validators.
- Creating a central configuration file, database, schema, receipt, migration service, or compatibility
  layer.
- Managing credentials, tokens, plan-local markers, SI/review runtime state, architecture lock promotion,
  or GitHub workflows.
- Making every implementation constant operator-configurable.
- Hiding the underlying canonical files or removing direct configuration paths.

## Definition of done

- `/skalary-config` supports guided and direct `show`, `bootstrap`, `edit`, `validate`, `diff`, `apply`,
  and per-key `reset` flows across the accepted categories; its catalog matches the final repository;
  all mutations are canonical, confirmed, synchronized, focused-validated, and reversible from the
  shown diff; excluded surfaces remain untouched; and uninstalling the skill leaves every subsystem
  directly configurable.
