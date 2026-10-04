# Domain Model

## Terms and meanings

- Workshop: concept exploration and codebase learning, not feature-delivery admission.
- Variant: one approved direction, its lightweight plan, isolated branch/worktree, prototype, and
  inspection instructions. Maximum three variants in one workshop.
- Vertical slice: runnable central behavior through its real connection/insertion points.
- Integration map: short entrypoint-to-behavior walkthrough naming interfaces, touched files/codepaths,
  and dependencies; Mermaid only where it improves understanding.
- Lightweight plan: concept sketch, tradeoffs, assumptions, touchpoints, a few steps, demo/check.
- Handoff: a self-contained explicit block carrying goal, selected variant identity, selection
  rationale, integration map, shortcuts/gaps, and open questions into the selected CIP context.

## Actors and boundaries

- Operator owns scope/set approval, post-inspection selection, and cleanup authorization.
- Workshop coordinator interviews, drafts alternatives, executes/coordinates approved prototypes,
  and synthesizes comparison. Use the host defaults, not a fixed premium model panel.
- Serial direct execution is the default. Native app children own one isolated slice each when
  approved/needed, within existing launch limits rather than a new orchestration exception.
- CIP owns actual plan creation, review, reconfirmation, and remaining production work.

## Interfaces and ownership

- `plugins/workshop/` owns the canonical skill and host/worktree asset.
- `.github/skills/ws/` is generated dogfood, not an independent source.
- App: native child project sessions/worktrees and returned session URLs.
- VS Code/CLI: direct Git worktrees plus tools/session context targeting that worktree; if tools
  cannot access it, request an explicit open/run action rather than editing the source checkout.
- Comparisons and lightweight plans use host artifacts/conversation, not formal plan directories.
  Handoff is sent explicitly to the winner session or pasted with CIP; forked context is not transport.

## Invariants

- Approved variants share the same recorded starting commit, goal, and central demo.
- Source checkout and other variants are not prototype edit targets.
- Set approval precedes execution; winner selection follows inspection.
- Correcting an approved concept does not introduce another direction. New concepts require set
  approval and count toward a lifetime cap of three, even when earlier variants are rejected.
- Selected worktree is a draft starting point; CIP may retain or redesign prototype code.
- Existing repository safety and architectural contracts remain applicable.
