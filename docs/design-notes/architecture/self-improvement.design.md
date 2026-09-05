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
states. The strict Markdown names the canonical plan id/slug and full source commit under `## Lessons`;
`None.` is the only empty marker, and each of at most 10 non-empty rows ends in one backtick-quoted
repo-relative citation. The reader caps the file at 16 KiB UTF-8, verifies the completed source commit,
ancestry and cited paths, refuses secrets/malformed input visibly, and returns accepted lesson text
inside a collision-safe untrusted-input fence. It does not scan historical workflow state.

The existing SI proposal-selection and lifecycle machinery remains temporarily unchanged for child
`3a4498 simple-self-improvement`; this cutover does not implement that later rewrite.
