# Intent

## Goal

Add `/ws` (workshop) to explore implementation concepts through runnable prototypes before creating
an actual `/cip` plan. Help the operator choose a direction and understand the target codebase.

## Desired outcome

Interview the operator, propose at most three distinct lightweight plans, obtain approval of the
set, and implement each approved direction in a separate branch/worktree. Compare the shape of
things: interfaces/layouts, connection points, insertion points, vertical integrations, and touched
codepaths. Select a prototype and start normal CIP planning in its worktree, with redesign allowed.

## Success signals

- A UI workshop exposes inspectable layouts/previews; a component workshop exposes interfaces and
  runnable usage examples, both integrated into enough surrounding code to explain the direction.
- The operator sees a comparable central vertical slice for every approved variant and can revise,
  reject, or choose after inspection.
- Peripheral stubs and unfinished detail are explicit; no prototype is presented as production-ready.
- Copilot app, VS Code, and terminal CLI have usable host-appropriate execution/inspection routes.

## Non-goals

- Production delivery, exhaustive edge cases, polish, broad suites, coverage targets, and hardening.
- Reviews, Judge calls, formal prototype plans, extra evidence bundles, and confirmation markers
  inside `/ws`. This implementation plan and subsequent CIP plans retain their normal gates.
- A new orchestration framework, scheduler, schema, state store, host adapter layer, or wrapper scripts.
- Automatic winner selection, hybrid merging, PR publication, or cleanup of alternatives.
- Applying the stashed implementation before the approved plan is executed.

## Definition of done

- Standalone plugin is packaged and dogfood-installed through existing distribution scripts.
- Interview, approval, isolated execution, integration comparison, selection, and CIP handoff are
  explicit instructions with focused contract/consumer checks.
- Operator/design docs and the CIP draft-input boundary agree with the skill.
- Implementation inspects the pinned stash for reusable material, adapting only approved parts.
- Full intent, requirements, risks, and decisions confirmed together before execution.
