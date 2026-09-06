# Domain Model

## Terms and meanings

| Term | Meaning |
|---|---|
| Configuration surface | A setting intentionally changeable by the operator, with a known source, default/precedence, consumer, and validator. |
| Canonical source | The file owned by a subsystem that an edit targets. Plugin sources are canonical; installed `.github/**` payloads and generated catalogs are not. |
| Effective value | The value a consumer will use after applying documented precedence, such as root project config over a shipped example. |
| Bootstrap | Create one selected missing optional surface from its subsystem-owned example or scaffold without overwriting an existing file. |
| Proposal | An in-memory set of canonical changes and required follow-up commands shown as one diff before mutation. |
| Preview digest | A transient digest of the canonical inputs shown to the operator; Apply refuses if those inputs changed and never persists the digest as state. |
| Synchronizer | An existing subsystem script that regenerates dogfood, catalogs, concern outputs, or other derived artifacts after canonical edits. |
| Advanced configuration | Maintainer-facing policy such as allowlists, plugin manifests, eval pins, or toolchains that needs stronger context and confirmation. |
| Model assignment | One role's primary model, replacement fallback, reasoning effort, context rule, canonical source, generated consumers, and focused validator. |

## Actors and boundaries

| Actor/boundary | Responsibility |
|---|---|
| Operator | Selects category, answers informed choices, reviews the proposal, and authorizes Apply. |
| `/skalary-config` | Discovers surfaces, explains precedence, builds the proposal, invokes existing writers/synchronizers/validators, and reports results. |
| Owning subsystem | Retains format semantics, defaults, schema where externally required, writer, validation, and direct configuration path. |
| Generated/dogfood boundary | Receives changes only through existing synchronization; never edited as authority. |
| Secret boundary | Reports only whether an approved credential source is available; values never enter prompts, diffs, or files. |
| Secret setup handoff | Printed acquisition/storage/login instructions followed by an operator-controlled pause; validation resumes only after the operator confirms separate-shell setup is complete. |
| Executable-setting boundary | Build/test/host command/container extension changes require an explicit warning and final confirmation. |
| Model-policy boundary | The façade edits the canonical role-specific sources delivered by `33a78a`; it does not invent routing semantics or consolidate them into a second authority. |

## Invariants

- There is no new source of truth: the catalog points to subsystem authorities.
- Discovery, show, diff, and validation are read-only until one explicit Apply decision.
- A proposal either completes canonical edits plus required synchronization or reports failure visibly;
  the skill does not claim a transaction/rollback protocol.
- Apply accepts only a closed category and known keys; no operator-supplied file path becomes a write
  target.
- Reset affects selected keys/surfaces only and derives defaults from current shipped examples.
- Unknown fields and unrelated settings survive.
- Generated outputs, state/history, secrets, locked architecture authority, and workflows are not ordinary
  configuration.
- Installed-consumer mode never assumes repository-maintainer tools that are absent; unsupported advanced
  categories are shown with the missing prerequisite.
- Authentication validation composes the installed credential reader and auth probes behind a
  secret-safe command boundary; raw values never become model-visible arguments or output.
- The model category covers autopilot, planning, implementation, CR/DR, independent review, and premium
  eval execution/judgment as one guided proposal while preserving each subsystem's canonical source.
- All shipped context selections are `default`; `long_context` is available only through an explicit
  cost-warned advanced choice.
