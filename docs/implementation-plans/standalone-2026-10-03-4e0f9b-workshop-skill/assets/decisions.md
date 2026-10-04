# Decisions

- Operator-confirmed: approve/revise the proposed alternative set before implementation.
- Operator-confirmed: inspect interfaces/layouts, connection/insertion points, vertical integrations,
  touched codepaths, and explanations that help understand the codebase.
- Operator-confirmed: runnable central vertical slice; peripherals can be drafted/stubbed.
- Operator-confirmed: actual CIP planning starts in the selected worktree, prototype redesign allowed.
- Operator-confirmed: support Copilot app, VS Code, and terminal CLI in the first version.
- Operator-confirmed: instruction-first plugin/native tools, not scripted orchestration.
- Accepted design: standalone `workshop` plugin, no planning dependency until handoff; native app children
  and direct Git worktrees elsewhere; host artifacts/conversation instead of new repo state formats.
- Accepted design: default to two or three useful concepts, one only on request or with a stated constraint.
- Accepted design: default serial direct worktrees, operator-approved app native children when needed
  within existing ceilings; host model defaults; no new global architecture exception or nested
  delegates/reviewers/automatic retry fleet.
- Accepted design: keep all prototypes; no implicit hybrid, merge, publication, cleanup, or CIP invocation.
- Operator-selected draft edits: self-contained explicit handoff transport into the selected CIP
  context; correct same concept versus reapproved new concept, lifetime cap of three including
  replacements; guide inventory/link changes; register plugin and consumer-smoke arm together.
- Implementation reuse is subordinate to this plan. Pinned stash is reference material only.
- This is the plan for building `/ws`: its normal CIP review/confirmation does not contradict the
  review-free prototype workflow that `/ws` will provide.
