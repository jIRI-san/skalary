# Intent

> Preliminary context captured from the `bcece1` epic discussion on 2026-08-14. `/cip` must confirm and refine it.

## Goal

Retire the unused architecture-test enforcement subsystem first, reducing the work surface for later workflow and receipt changes while preserving the useful human-reviewed architecture-notes and ADR workflow.

## Desired outcome

The architecture-tests plugin, runner, adapters, receipts, configuration, schemas, `arch:` evidence marker, tests, distribution entries, and stale documentation are removed coherently. Fresh consumers cannot install it. Existing same-source consumers first receive a non-destructive preview, then remove unmodified payload on a later reconciliation-capable install/update while preserving and reporting modified residue. Architecture notes remain an always-on human-owned contract and decision tier whose locked content is digest-pinned, but no plan claims executable architecture evidence the repository does not use.

## Success signals

- No installed or source payload references the retired architecture-test runtime.
- Existing consumers converge through a permanent, source-bound, preview-first retirement tombstone without deleting modified files.
- Plan evidence and validators reject or migrate away from `arch:` markers without false-green compatibility behavior.
- Registry, marketplace, dogfood, tests, design notes, and active plan references agree on the retirement.
- Architecture notes, digest-pinned human-owned maturity, human-doc freshness, and ADR harvesting remain functional and documented.

## Non-goals

- Deleting the architecture-notes tier or its human review and ADR promotion workflow.
- Replacing architecture tests with another semantic enforcement framework in this plan.
- Reopening unrelated plan evidence contracts.
- Garbage-collecting plugins absent from a registry without an explicit same-source retirement tombstone.
- Rewriting archived plans, transcripts, or historical reports.

## Definition of done

- The repository, fresh consumer installs, and preview-then-reconciled existing consumers have no architecture-test execution surface; modified consumer files remain explicitly owned and reported; locked architecture knowledge remains human-owned and content-pinned; and no active workflow references removed contracts.
