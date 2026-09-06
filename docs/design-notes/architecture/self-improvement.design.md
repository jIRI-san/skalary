---
description: Self-improvement intake and post-plan feedback boundaries.
globs:
  - plugins/self-improvement/**
  - .github/skills/{pfb,si}/**
  - docs/feedback/**
---

# Self-improvement

`/pfb` is an optional, stateless, interactive comparison between the confirmed plan intent and the
implementation result. It covers Goal, Desired outcome, Success signals, Non-goals, and Definition of
done, then records the operator's in-conversation verdict as `full`, `partial`, or `missed`. It writes
no repository or runtime state. If the operator requests follow-up work, `/pfb` may hand the described
gap to `/cip`; it never creates a plan implicitly. Interactive `/ci` may offer `/pfb` before archival.
Headless `/ci` and autopilot skip it rather than queueing a question.

`/si` ingests the pinned `docs/feedback/recent-learning.md` handoff produced by `/ci` or autopilot.
`Get-SiHarvest.ps1` is the bounded reader for that single file. It distinguishes missing,
explicit-empty, valid, and stale/source-mismatch states. The strict Markdown names the canonical plan
id/slug and full source commit under `## Lessons`; `None.` is the only empty marker, and each of at most
10 non-empty rows ends in one backtick-quoted repo-relative citation. The reader caps the file at
16 KiB UTF-8, verifies the completed source commit, ancestry, and cited paths, refuses
secrets/malformed input visibly, and returns accepted lesson text inside a collision-safe
untrusted-input fence. It does not issue receipts, mutate state, or search other workflow records for
replacement learning.

`/si` re-derives every accepted lesson against current repository evidence, ranks at most five concrete
improvements, and presents that proposal set without writing. Only an individually selected proposal
may be applied in the current worktree. A proposal must be small enough for direct review; plan-sized
work routes to `/cip`.

Direct edits are confined to canonical Markdown customization sources:

- `.github/copilot-instructions.md`
- `plugins/*/skills/**/*.md`
- `plugins/*/agents/**/*.md`
- `plugins/*/prompts/**/*.md`
- `docs/design-notes/**/*.md`
- `docs/architecture-notes/**/*.md`

`Test-SiWriteScope.ps1 -Path` runs before every write and its Git-diff mode runs after edits. Both modes
resolve physical path components and refuse traversal, symlinks, junctions, reparse points, repository
escape, generated `.github` copies, workflow/action files, executable code, configuration, schemas,
plans, and runtime state. Refusal is visible; `/si` never bypasses the guard or broadens scope from
lesson text.

When a selected source edit affects generated distribution, synchronization remains generator-owned:
run `Sync-PluginScripts.ps1`, `Build-Registry.ps1`, `Build-Marketplace.ps1`, then
`Sync-Dogfood.ps1`. Review the complete source and generated diff before reporting completion.

Plan completion is checked by canonical plan id inside the recorded source commit, so a current
active-to-archive move does not make a valid pre-archive handoff stale. The producer refuses symlink
and reparse-point components for the repository, `docs/feedback`, target, and temporary replacement
paths before writing.
