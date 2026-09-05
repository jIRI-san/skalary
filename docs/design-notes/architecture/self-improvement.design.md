---
description: Self-improvement intake and post-plan feedback boundaries.
globs:
  - plugins/self-improvement/**
  - .github/skills/{pfb,si}/**
  - docs/feedback/**
---

# Self-improvement

`/pfb` remains an optional non-blocking operator feedback flow. Its queue and write-scope guard are
unchanged.

`/si` now ingests only the pinned `docs/feedback/recent-learning.md` handoff produced by `/ci` or
autopilot. `Get-SiHarvest.ps1` distinguishes missing, explicit-empty, valid, and stale/source-mismatch
states, caps the file at 16 KiB, and returns valid content inside a collision-safe untrusted-input fence.
It never scans review ledgers, plan logs, overflow batches, or phase receipts.

The existing SI proposal-selection and lifecycle machinery remains temporarily unchanged for child
`3a4498 simple-self-improvement`; this cutover does not implement that later rewrite.
