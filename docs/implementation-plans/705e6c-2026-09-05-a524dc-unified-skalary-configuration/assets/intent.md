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
- The model ladder is one first-class configuration category: six stable low/mid/high primary and
  alternate aliases, host bindings, role assignments, reasoning effort, default-first context with
  explicit long-context opt-in, autopilot default, CR/DR routing, and waza executor/judge assignments.
- Model configuration shows the 180K operating budget and 20K reserve, current canonical sources,
  effective values, and every generated/dogfood consumer before proposing a change.
- Missing optional configuration is created only when the operator selects that surface.
- Every displayed value names its canonical source, default, precedence, generated copies, consumer,
  synchronizer, and focused validator.
- Apply writes no generated/dogfood copy directly and leaves no synchronization drift.
- Unknown fields and unrelated settings survive edit and per-key reset.
- Secrets are never displayed or persisted; only credential-source availability is shown.
- Runtime state, plans, receipts, schemas, retirement history, generated catalogs, and workflows are
  excluded or explicitly read-only.
- Focused tests cover discovery, precedence, bootstrap, diff-before-write, cancellation, apply,
  reset, source synchronization, secret refusal, executable-setting confirmation, invalid models,
  invalid role/fallback combinations, default context, and explicit long-context opt-in.

## Non-goals

- Replacing subsystem-owned configuration formats or validators.
- Creating a general central configuration file, database, receipt, migration service, or compatibility
  layer. The existing canonical model alias map is an accepted narrow exception.
- Managing credentials, tokens, plan-local markers, SI/review runtime state, architecture lock promotion,
  or GitHub workflows.
- Making every implementation constant operator-configurable.
- Hiding the underlying canonical files or removing direct configuration paths.

## Definition of done

- `/skalary-config` supports guided and direct `show`, `bootstrap`, `edit`, `validate`, `diff`, `apply`,
  and per-key `reset` flows across the accepted categories; its catalog matches the final repository;
  all mutations are canonical, confirmed, synchronized, focused-validated, and reversible from the
  shown diff; excluded surfaces remain untouched; and uninstalling the skill leaves every subsystem
  directly configurable. Every alias, host binding, role assignment, and context default is visible and
  changeable through the model category via the canonical model map and existing synchronizers.
