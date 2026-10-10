# App CI coordinator

This route is app-only. Retain the root skill's criteria, evidence, model, permission and completion
guards. Native app sessions are full isolated worktrees, not subagents. Docker and Windows Sandbox
workers remain isolated CLI processes, not native remote attachments.

## Admission and kickoff

Resolve installed `.github/skills/ci/scripts/Get-PlanState.ps1 -Reference <id> -RepoRoot <root>`.
Check the Git criteria baseline before every mutation. Confirm the requested extent and environment
if absent: one phase or whole plan; local, container or sandbox. In unattended mode exhaust admitted
AI work, but never authorize human steps. The app's legacy `host` selection means native local
sessions; do not change VS Code's host selection or user config.

Inspect the current session, integration branch/full HEAD, worktree cleanliness and existing child
activity. Record identities in native conversation context, not a new journal. If ownership is
ambiguous, stop with `42`; do not start another writer. Keep integration HEAD and checkout unchanged
while the worker runs. Use only one worker at a time.

For local execution call app `create_session` with the current project, `workspace_type: "worktree"`,
`base_branch` explicitly set to the integration branch, and `coordinate_with_creator: true`.
Bind `kickoff.model: "gpt-6.1-sol"`, `reasoning_effort: "high"`, `context_tier: "default"`,
`mode: "interactive"` (never default plan mode), and `agent: "autopilot"`.
The user's fresh-phase request authorizes the explicit base branch. Do not omit settings or inherit
Auto, reasoning or long context. Never silently substitute a model or another client/runtime.

Kickoff names **App CI worker**, canonical plan ID, one phase number or `finalization`, expected full
starting commit, integration branch, environment, admitted step IDs and unattended policy. Quote the
relevant user request and separate confirmed criteria from implementation suggestions. Require the
worker to verify its distinct worktree and exact HEAD before mutation, load current plan assets,
repeat the baseline, implement directly, run focused current evidence and commit source/checklist
progress atomically. No phase/child PR, recursive coordinator or whole-plan loop. A phase visit never
finalizes. Attach at most three artifacts; target 400 words and narrow before 800.

## Retained isolated dispatch

Launch from a separate owned transport worktree at the integration commit, not the integration
checkout: launchers use its config and remote. App output/usage remains outside Git until import.
Resolve/generate runtime config there through
existing approved config handling; never copy credentials or arbitrary host state. The shared
launcher owns toolchains/auth/feed/output/usage and runtime-specific blocking waits.

Invoke installed `.github/skills/autopilot/scripts/launch.ps1` directly with `-PlanSlug <folder>`,
`-Mode app-phase -Phase <number>` or `-Mode app-finalization`, `-Runtime container|sandbox`,
`-Branch <source-branch>`, `-ExpectedStartCommit <full-head>`, and a fresh explicit
`-WorkerBranch <work-ref>`. These modes bind Sol high/default in memory without changing saved config.
One invocation executes one target, never a whole-plan loop or worker PR.

Existing remote Git transport requires explicit permission to publish the source/work branch.
If that permission is absent, stop; do not turn selected isolation into a local fallback.
Keep `0` complete, `42` operator action, `43` offline rebundle and other failures distinct.
Use existing bounded rebundle handling; a rebundle's changed work head must be inspected on return,
not represented as the original starting HEAD. Preserve work branches, container/session outputs and
sidecars until local acceptance. Do not delete a work-bearing native session or runtime.

## Observation, local acceptance and resume

Use authoritative app session activity/metadata and messages, or owned runtime process/container
state plus exact launcher exit. Idle, transcripts, sentinels and a worker's success message are not
proof. A blocked question/plan requires operator action, not self-approval.

Fetch only the known isolated work ref into the transport checkout, with existing permissions, and
verify its ancestry from the expected start. Import that exact ref into the integration repository
using local Git fetch from the owned transport checkout, not broad file copying. First check out the
verified worker head in the clean transport worktree; never normalize usage against its old active
plan. Then use installed `Record-AiCreditUsage.ps1` on each exact retained sidecar, with its target,
runtime, Sol alias and default context. Commit only the exact archive-aware plan-local ledger before
import. Retain sidecars until accepted; reimport is idempotent. Sandbox's local `worker-result.bundle`
is a recovery source when permitted remote transport failed: verify Git bundle integrity/ancestry and
inspect the exact known result before import. Recovery patches/untracked files are local inspection
only, not automatically staged, published or accepted. Never fabricate native app usage or import secrets.

After the worker stops, run installed `.github/skills/ci/scripts/Test-AppCiWorkerResult.ps1` with
`-IntegrationRoot <root> -WorkerRoot <worker-or-transport-root> -PlanReference <id>`
`-ExpectedStartCommit <head> -Phase <number>` or `-Finalization`.
It checks clean isolated Git identities, unchanged integration HEAD, ancestry, criteria, immutable
checklist structure and phase-local committed progress. It does not certify source scope or test
success: inspect the actual diff against confirmed scope, run the required focused evidence locally,
and call `Invoke-DirectEvidence` with current results before acceptance. Out-of-scope work or failed
evidence stops with recoverable commits. For finalization verify review/learning/archive ordering and
current completion guards, not persisted review authority. Mechanical finalization requires this
completed active source, its immediately following learning commit and a separate later archive commit.

Only after all checks pass, import the exact worker commit and `git merge --ff-only <full-head>`.
On `42`, inspect the named blocker and independently revalidate committed unaffected progress before
any acceptance; never auto-accept or continue because a commit exists. `43` is not partial success.
On resume reconcile known activity, ancestry and checklist state first. If the known result is already
an ancestor of integration HEAD, do not integrate or dispatch it again. A new phase visit starts from
the accepted current HEAD. Divergence, dirty state or unknown active ownership stops; never stash,
reset, force-push or silently resolve conflicts.

## Readiness, decisions and completion

Within the first unfinished phase, execute dependency-ready AI siblings around human blockers.
Every earlier phase must close before later phases, even without explicit dependency annotations.
Use current metadata/dependency helpers; never equate `NextStep.IsHuman` with no independent work.
For the first unfinished phase use installed autopilot `Get-PhaseExecutionState.ps1` with
`-AllowIndependentAi`. That explicit app-only option selects a ready AI sibling before canonical
admission and returns `operator-action` when only human/dependent work remains; it does not grant
later-phase exemption. Load current `PlanState.psm1` metadata to name admitted AI IDs whose `After`
prerequisites are already completed. Re-evaluate after each atomic step; never credit human work.
A partial phase stays open; a later admitted visit has a fresh worker context. If no AI work is ready,
report incomplete with remaining human/dependency actions, not whole-plan success.

Write bounded decisions only when needed to the existing plan's `assets/unattended-decissions.md`.
Each entry names step/criterion, choice, rationale and consequence; use existing confinement and
secret screening. Commit coordinator entries only between worker intervals. This mutable log cannot
override confirmed criteria. Material choices stop affected work through CIP reconfirmation; only
independently admitted unaffected work may continue. Present decisions/blockers on exhaustion.

After all required phases close, dispatch one fresh finalization worker with the same exact settings.
It owns current final evidence, one unchanged-scope terminal CR, conditional compaction, committed
recent learning and archive move, using the root skill's helpers. All-closed unarchived plans still
need this target; already finalized archived plans do not. Headless skips PFB. Human compaction,
deletion or push gates stop visibly. No worker PR.

For app epics, inspect current child dependencies and criteria, select independently admitted child
work serially, and use the same plan lifecycle. Do not invoke the competing host-only epic wrapper.
Use `Get-EpicRollup` for membership/dependency facts, but inspect each dependency-ready child's app
phase admission rather than treating its first human `NextStep` as an exhausted child. Finalize and
integrate each child before launching dependents; its committed archive, not a child PR, is app proof. Do not invoke the competing host-only epic wrapper.
Do not use per-child provider PRs as new app completion proof. Each child must finalize/archive once.
After all child finalizations are integrated, verify the epic Goal/Definition-of-done/coherency,
refresh/archive the epic index through installed autopilot `Archive-Epic.ps1`, and commit it.
An all-child-archives resume still performs pending epic completion, not another child finalization.
Retained VS Code epic wrapper/provider proof remains unchanged.

Only the coordinator owns delivery: after all requested-run completion gates and integrated learning/
archive commits, use the app PR creation tool for at most one final PR. Preserve explicit push guards
and the established PR base; inspect an existing exact-run PR before creating another. No automatic
GitHub merge, deployment or cleanup is authorized. Human live acceptance in the implementation plan
remains blocking; static contract tests do not prove live app/runtime settings.
