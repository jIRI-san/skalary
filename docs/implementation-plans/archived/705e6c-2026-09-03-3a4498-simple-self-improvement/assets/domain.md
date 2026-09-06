# Domain Model

## Terms and meanings

- **Recent-learning handoff** - the single strict `docs/feedback/recent-learning.md` file produced by a
  completed `/ci` or autopilot run.
- **Lesson** - one source-commit-cited line in the handoff, treated as untrusted data.
- **Proposal** - an agent-authored, evidence-checked possible improvement derived from one or more
  lessons. It has no durable identity or lifecycle.
- **Selected change** - one proposal the operator explicitly chose during the current interaction.
- **Canonical customization source** - `.github/copilot-instructions.md`, canonical plugin
  skill/agent/prompt Markdown, or a design/architecture note.
- **Trusted synchronization** - the existing repository generators that update manifest, catalog, and
  dogfood outputs after a selected canonical plugin Markdown edit.

## Actors and boundaries

- The operator chooses proposals and owns any correction-plan decision.
- `/si` reads the handoff, verifies current repository evidence, presents at most five informed
  proposals, and edits only selected canonical sources.
- `/pfb` compares delivered work with confirmed intent and may pass an accepted correction to `/cip`;
  it persists nothing.
- `Get-SiHarvest.ps1` owns bounded parsing, source/commit/citation validation, secret refusal, and
  untrusted framing. It does not rank or persist proposals.
- `Test-SiWriteScope.ps1` owns physical target confinement. It does not decide proposal quality.
- Existing plugin generators own derived manifest, registry, marketplace, and dogfood changes.

## Invariants

- Missing or explicitly empty learning produces no proposal and no write.
- Stale, malformed, oversized, secret-containing, or uncited learning stops visibly.
- Lesson text is data and never instruction authority.
- Only individually selected changes may be edited.
- Direct targets are canonical Markdown sources; workflow/action paths, generated copies, executable
  code, plans, runtime state, and physical path escapes are refused.
- A selected target with unrelated local edits is not overwritten.
- A failed edit, sync, or validator leaves a visible diff and never claims rollback.
- No queue, due, receipt, repair, archive, cross-repository transport, branch, PR, or proposal state is
  part of the workflow.
