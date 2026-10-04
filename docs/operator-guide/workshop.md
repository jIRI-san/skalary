# Exploring concepts with `/ws`

Use `/ws <idea>` before `/cip` when the implementation direction is unclear and a small runnable
prototype can teach you how the idea fits the codebase. `/ws` is an exploration route, not a
production plan. Install the standalone `workshop` plugin; `/cip` is needed only when you ask to
begin actual planning.

## Approve concepts before implementation

The skill asks about the intended outcome/users, concept axis, constraints, and smallest useful demo.
It proposes up to three genuinely different concepts, each with a concrete sketch, likely code
touchpoints, tradeoffs, and focused demo/check. Approve or revise the entire set before worktrees or
implementers start; this does not select a winner. The lifetime cap is three distinct concepts,
including rejected and replacement directions. A correction within the same approved concept does
not consume another slot.

## Compare runnable integrations

Every approved concept starts from one recorded Git SHA in its own branch/worktree. A prototype must
run through the central code path and real entrypoint/connection/insertion points; peripheral mocks
are allowed only when identified. A UI comparison exposes inspectable layouts/previews on separate
ports. A component/API comparison includes its interface and executable usage. The report names the
source layout, entrypoint, integration path, touched files, demo and check, and any shortcuts or
untested behavior. A blocked prototype stays visible as blocked. Focused checks are not evidence of
production readiness.

## Worktree hosts and retention

Copilot app can use approved native child worktree sessions; specify the source branch rather than
assuming the project default and verify the expected SHA before edits. VS Code and terminal CLI use
direct Git worktrees by default, opened in a context that can target each path. If the host cannot
access an isolated worktree, stop and request an explicit operator action. Dirty starting changes
require a checkpoint or an explicit committed-HEAD choice; the workflow does not stash or copy them.

Inspect all variants before choosing. The selected branch remains the starting point; rejected
variants stay available. Selection does not merge, publish, delete, or invoke CIP automatically.

## Explicit CIP handoff

When you request planning, verify the selected branch/path/session and prototype commit. Transfer the
complete handoff to that app session, or paste it alongside `/cip` in the selected VS Code/CLI
worktree. Include the goal, common base, chosen identity, selection rationale, integration map,
demo/check outcome, shortcuts, gaps, and open questions. If the identity changed or the CIP plugin is
unavailable, stop for an operator decision. CIP reconfirms the goal and may redesign the prototype;
the handoff and prototype are draft input, not confirmed criteria or completed work.
