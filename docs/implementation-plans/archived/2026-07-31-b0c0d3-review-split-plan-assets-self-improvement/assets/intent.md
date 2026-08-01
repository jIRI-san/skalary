# Intent

<!-- Retro-captured at migration time: this plan predates the /cip intent gate (REQ-4). -->

## Goal

Make the plan/review toolchain scale: split monolithic `plan.md` into `plan.md` + `assets/`, replace the
per-model review agents with model-agnostic concern reviewers on two models, and close the loop from
delivered work back into the repo's own skills.

## Desired outcome

- A plan folder whose root holds only `plan.md`; every other concern is an addressable, on-demand asset.
- `cr` / `dr` that review by concern rather than by model, over a changed-file list rather than extracted diffs.
- `/pfb` + `/si` turning post-plan feedback and harvested learnings into reviewable, never-auto-merged proposals.

## Success signals

- Every REQ in `assets/requirements.md` proven by its typed evidence markers in `assets/evidence.md`.
- Legacy and archived plans keep validating byte-for-byte unchanged through the dual-layout resolver.
- No skill, agent, or prompt reads an asset that installation does not materialize.

## Non-goals

- Migrating existing or archived plans to the new layout; the dual path is permanent, not a window.
- Cross-repo PR automation for consumer repos (`gh` fork entitlement is out of scope).
- Detecting a runtime model downgrade — declared configuration is validated; the served model is not observable.

## Definition of done

All ten phases complete, `npm test` green, requirements and risks crosschecked in `assets/evidence.md`
with no `✗`/unrun markers left undeferred, and the design notes updated to match the shipped behaviour.
