# Intent

## Goal

Reduce the repository's script and compatibility surface by deleting proven-dead or completed
machinery and simplifying the three largest active workflow modules without changing their supported
behavior.

## Desired outcome

The repository has one smaller, current implementation path for plugin-retirement validation, plan
folder naming, architecture notes, epic orchestration, work-hierarchy synchronization, and direct
workflow primitives. Historical snapshots and generated compatibility documents no longer preserve
retired implementations as active maintenance obligations.

## Success signals

- Dead wrappers and the completed plan-folder migration are gone together with their dedicated tests.
- The architecture-test retirement snapshot is replaced by a small current-state absence check.
- Markdown architecture notes remain authoritative without a generated human-document compatibility
  chain.
- `EpicAutopilot.psm1`, `WorkHierarchy.psm1`, and `DirectWorkflow.psm1` each contain fewer private
  functions and fewer non-comment source lines while retaining their exact public exports and focused
  behavior.
- Plugin manifests, registry data, installed dogfood copies, tests, and active documentation agree
  with the reduced source tree.

## Non-goals

- Removing or changing `plugins/autopilot/scripts/clean-sandbox-cache.ps1`.
- Removing supported host, container, or Windows Sandbox execution modes.
- Removing work-hierarchy capabilities, recovery guarantees, or provider boundaries.
- Changing direct-review, criteria-baseline, evidence, or report semantics.
- Splitting the three large modules into more production modules merely to reduce individual file size.
- Migrating additional historical plan folders or preserving the retired migration as a general tool.
- Removing the remaining legacy JSON architecture contract, its direct validation, ADR import, or
  Markdown architecture-note workflow.

## Definition of done

- Every named retired surface is absent from canonical source, generated copies, manifests, tests, and
  active guidance.
- The retained sandbox-cache cleanup command remains installed and documented at its current boundary.
- Structural evidence proves a net private-function and non-comment-line reduction in each large module
  from the recorded baseline, without compressed formatting or relocated production machinery.
- Existing focused behavior suites and generated-distribution checks pass against the simplified code.
- Architecture and design notes describe only the resulting current system.
