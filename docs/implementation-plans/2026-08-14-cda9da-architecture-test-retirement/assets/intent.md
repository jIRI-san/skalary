# Intent

> Preliminary context captured from the `bcece1` epic discussion on 2026-08-14. `/cip` must confirm and refine it.

## Goal

Retire the unused architecture-test enforcement subsystem while preserving the useful human-reviewed architecture-notes and ADR workflow.

## Desired outcome

The architecture-tests plugin, runner, adapters, receipts, configuration, schemas, `arch:` evidence marker, tests, distribution entries, and stale documentation are removed coherently. Architecture notes remain an always-on contract and decision tier, but no plan claims executable architecture evidence the repository does not use.

## Success signals

- No installed or source payload references the retired architecture-test runtime.
- Plan evidence and validators reject or migrate away from `arch:` markers without false-green compatibility behavior.
- Registry, marketplace, dogfood, tests, design notes, and active plan references agree on the retirement.
- Architecture notes and ADR harvesting remain functional and documented.

## Non-goals

- Deleting the architecture-notes tier or its human review and ADR promotion workflow.
- Replacing architecture tests with another semantic enforcement framework in this plan.
- Reopening unrelated plan evidence contracts.

## Definition of done

- The repository and consumer install have no architecture-test execution surface, while architecture notes remain usable and no active workflow references removed contracts.
