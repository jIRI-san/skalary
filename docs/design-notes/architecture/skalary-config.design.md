---
description: Unified read-only Skalary configuration catalog and bounded category discovery.
globs:
  - plugins/skalary-config/**
  - tests/skalary/SkalaryConfig.Tests.ps1
---

# Skalary configuration

## Architecture

`skalary-config` is a façade, not a configuration authority. Its Markdown catalog describes the closed
accepted categories and points to their existing canonical sources, defaults, generated outputs,
precedence, sensitivity, bootstrap owner, synchronizer, validator, and installed-consumer availability.

The read-only script owns a fixed PowerShell category map; it never executes or derives policy from the
catalog. It detects source versus installed-consumer layout, permits no arbitrary paths, rejects linked
canonical files, reports only fixed metadata, and computes a transient digest from canonical non-secret
file bytes. Credential values are never read.

`Set-SkalaryConfig.ps1` is the separate closed mutation adapter. It previews and applies only
`autopilot`, `local-review-standards`, and `models-reviews`; Apply needs the preview digest, writes one
canonical path, and preserves unrecognized JSON keys and unmanaged Markdown. Model edits change only
`tools/model-allowlist.psd1`, then run `Sync-ModelBindings.ps1` and `Test-ModelAllowlist.ps1`. Autopilot
build/test/runtime/container settings need an explicit warning acknowledgement, and `long_context` needs
an explicit cost acknowledgement. `Test-AutopilotAuth.ps1` retrieves a credential internally through the
installed autopilot reader, composes its validator, and returns only target availability and capabilities.

The remaining category routes are read-only owner handoffs. Terminal approval discovery parses JSONC
and lists only exact approved `Get`/`Find`/`Test`/`Validate` skill scripts before naming
`Set-ScriptApproval.ps1`. Eval discovery reports credential target names and Waza model/judge bindings
without reading credential values. Design and architecture discovery reports tier scaffold status and
the owner scaffold commands. Plugin distribution and repository/toolchain policy remain advanced,
source-only status routes; manifests, eval specs/pins, and tool pins have no generic façade writer.

Apply is category-bounded: it rechecks the preview digest before writing, then runs the model binding
synchronizer followed by its allowlist validator. A write, synchronization, or validation failure
throws a non-success error that explicitly states no rollback was attempted, retains the Git diff, and
provides the category's direct recovery command.

## Constraints

- Generated registry, marketplace, README, dogfood, receipts, plan/runtime state, workflows, and
  architecture lock promotion are never configuration targets.
- An installed consumer reports unavailable advanced maintainer categories instead of guessing source
  tools.
- `preview` is read-only and has no durable proposal state. Its digest lets a later mutation flow refuse
  changed canonical inputs.
