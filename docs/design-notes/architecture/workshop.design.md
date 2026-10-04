---
description: Instruction-first concept workshops, isolated runnable prototypes, comparative integration maps, and explicit draft handoff to CIP.
globs:
  - plugins/workshop/**
  - .github/skills/ws/**
  - tests/skalary/Workshop.Tests.ps1
---

# Workshop

## Architecture

`/ws` is an independent skill plugin. The skill owns the interview, whole-set approval, prototype
scope, comparison, selection, and handoff; `assets/worktrees.md` owns host-specific isolation steps.
It adds no runtime scripts, review/planning dependency, wrapper, state store, or formal plan. Host
conversation/session artifacts describe concepts and comparisons; Git branches/worktrees retain
prototype code.

## Key Patterns

- Ask only for outcome/users, concept axis, constraints, and the smallest informative demo; reuse
  answers and leave production detail as explicit draft assumptions.
- Offer no more than three distinct concepts over the workshop lifetime. Approval covers the full
  proposed set before prototype work starts; selection occurs only after inspection. Corrections
  within a concept do not consume another slot; replacement directions require approval and count.
- Start each approved variant from one recorded SHA in its own worktree. Terminal/VS Code use direct
  Git worktrees by default; the Copilot app may use approved native child worktree sessions.
- Implement the real central vertical path through repository entrypoints and insertion/connection
  points. Peripheral stubs are named; demos, checks, touched paths, integration maps, and gaps are
  compared together. Keep blocked variants visible.
- Explicitly transport the selected variant's goal, identity, decision, integration map, demo/check,
  gaps, and open questions to the chosen CIP context. CIP verifies identity and treats it as draft.

## Design Decisions

No winner is inferred from tests, no hybrid is assembled implicitly, and selection authorizes no
merge, PR, or cleanup. All variants remain inspectable until the operator explicitly authorizes
cleanup. `/ws` does not invoke CIP; its normal review and confirmation gates own production planning.

## Constraints

Use one focused demo/build/type check per variant, not broad suites or production hardening. Stop if
the base SHA or host worktree identity cannot be verified. Static prompt contracts do not establish
live host behavior; unavailable host checks remain outstanding.

## Dubious decisions

Prototype checks establish enough confidence to compare the central concept, not production
readiness. Disclosed stubs and untested edges travel in the draft handoff for CIP to re-evaluate.
Direct SHA checks are not a lock against concurrent source-branch movement; variants refuse an
initial mismatch and require an operator-agreed base rather than adding coordination machinery.
