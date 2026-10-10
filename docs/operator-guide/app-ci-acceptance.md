# App CI live acceptance

These are operator-owned rollout gates, not automated-test results. Run each fixture only after
approving its session, source branch/full commit, selected isolation, auth/feed prerequisites and
remote publication boundary. Use disposable work surfaces based on the implementation commit.
Never test by marking this implementation plan's human steps complete in a worker.

## Confirmed two-phase fixture

Create a separate disposable plan through `/cip` for each environment. Pick a fresh six-hex ID and
name `app-ci-smoke-<environment>`, check for collisions, and keep all implementation inside
`smoke/app-ci/<id>/`. Confirm the following intent and criteria through the normal planning flow,
including its confirmation commit; do not hand-write a confirmation hash.

**Goal:** prove bounded fresh workers, human-safe readiness, exact-head integration, resume and one
finalization. **Non-goals:** change Skalary, merge a PR, deploy, delete work or expose credentials.
**Done:** files below contain the exact named text, human approval is recorded, all phases close with
current evidence, and learning/archive commits plus the allowed final PR boundary are inspected.

Use this checklist, with `S` sizing and observable outcome/constraint/verification details:

```markdown
## Phase 1: Human-safe readiness

- [ ] 1.1 Authorize dependent fixture work @human `S`
- [ ] 1.2 Write independent.txt with `independent` and an LF newline `S`
- [ ] 1.3 Write dependent.txt with `dependent` and an LF newline [after: 1.1, 1.2] `S`

## Phase 2: Accepted-head continuation

- [ ] 2.1 Write second.txt with `second` and an LF newline [after: 1.3] `S`
```

Requirements bind repository-relative `file:smoke/app-ci/<id>/<name>.txt#contains:<text>` markers
plus focused byte assertions for each LF-terminated file. The human step has no worker completion
permission. A bounded choice in 1.2 is how to produce the required LF bytes; record the method,
criterion, rationale and consequence in `assets/unattended-decissions.md`, without changing criteria.
No source file or design note outside the fixture subtree is changed, apart from required plan
progress/learning/archive and exact isolated usage.

Keep auth/feed configuration local and ignored. Confirm a clean starting Git tree and record its
full HEAD as `H0`. The native coordinator's branch stays fixed during every worker interval.
Each later visit binds the full accepted current HEAD, not `H0` reused indefinitely.

## Native app gate (6.1)

Start a disposable coordinator in the Copilot app. Request:

> Run /ci <fixture-id>, whole plan, local, unattended. Use fresh GPT-6.1 Sol/high/default workers.
> Do not authorize the human step, create worker PRs, merge a PR, deploy or clean up. Preserve
> decisions and work. Stop before final publication unless I explicitly authorize it.

Inspect the first child using app metadata and the model picker: a full independent session/worktree,
Sol/high/default and execution mode, correct project/branch, exact `H0`, no host launcher or recursive
coordinator. If metadata/settings cannot be observed, stop and record a capability failure; do not
infer them from inheritance or the worker's claim.

The first child completes only 1.2 and returns the human/dependency blocker. Inspect its atomic
source/checklist commit and current byte evidence. After local acceptance, integration HEAD is `H1`,
1.1/1.3/2.1 remain unchecked, and Phase 1 is open. Capture the decision handoff.

Resume once without human approval: no new worker or finalization should run. Explicitly authorize
1.1 in the coordinator, record only that human mark and commit it, then resume. A fresh Phase 1 visit
starts at this accepted HEAD and completes 1.3 without rewriting 1.2. A fresh Phase 2 visit starts at
the next accepted HEAD and completes 2.1. Inspect each child/commit pair and local fast-forward.

After both closures, inspect exactly one finalization child. Source, strict recent learning and
archive commits are ordered; the plan re-resolves by ID in the archive. Final current evidence and
review are required, not an old Markdown report. With publication permission absent, stop visibly.
After explicit permission, the coordinator may create one PR on the agreed base, never a phase PR.
Resume again: archived plan, integrated results and existing exact-run PR are not repeated.

## Docker gate (6.2)

Use an independently confirmed copy of the fixture and an owned transport worktree at `H0`. Approve
Docker, the existing auth/toolchain configuration, and publication of only the named source/work
refs. Configure the existing offline feed and rebundle cap where the fixture exercises packages.
The app invokes the installed launcher; the operator does not manually run CLI phases.

Inspect each uniquely named container and actual CLI flags: Sol/high/default, original ancestry,
current expected worker HEAD, `app-phase -Phase N` or `app-finalization`. Docker isolation is real;
the app process sandbox or cloud sandbox does not substitute. Repeat the native human/partial/resume
sequence with fresh bounded invocations and no legacy PR-close loop.

Compare launcher exit with local inspection: `42` is partial/operator action, not phase closure;
`43` is rebundle, not success. Exercise a missing-package rebundle in a package-bearing disposable
fixture using the existing feed contract: preserve the manifest/work ref, rebuild within the cap,
verify the retry's actual new HEAD and original ancestry, and refuse exhaustion. Do not introduce a
new dependency into Skalary to provoke this.

Verify exact sidecars and transcripts survive outside Git. Check out the inspected result in the
transport worktree before importing usage; commit the exact ledger, then verify current scope/evidence
and fast-forward integration. Reimport the same execution: its count/credits do not increase.
Finalization usage follows the archived plan, never recreating an active plan folder.

Force a controlled publication failure using the disposable fixture's approved transport boundary,
without revoking shared credentials: the named container, commits, dirty work and sidecars remain
recoverable and local integration does not advance. Inspect recovery before an authorized retry.
The launcher never auto-stages dirty app work or deletes its container.

## Windows Sandbox gate (6.3)

Use another confirmed copy on a host with Windows Sandbox, the configured toolchain cache, auth and
approved source/work ref publication. Review only the documented read-only repo/runtime/cache/feed
and writable session-output mappings. No arbitrary host state or credentials become payload.

Repeat the same human/partial/resume/finalization sequence. Inspect the disposable Windows runtime
and real Sol/high/default CLI invocations at their exact heads; no native attachment claim. A
sentinel/exit marker alone is not acceptance. Inspect current commits/evidence and controlled Git
transport before advancing integration.

Exercise bounded offline rebundle and usage idempotence as in Docker. Verify output survives
teardown: transcripts, exact sidecars, `worker-result.bundle`, and, for a controlled dirty failure,
the tracked recovery patch plus ordinary non-ignored untracked files. Verify the bundle before
import; dirty recovery is inspection-only, not automatically published or accepted. Missing/corrupt
transport, invalid markers, wrong HEAD or linked recovery paths fail visibly. Preserve the Sandbox
on a recovery failure rather than discard its only work copy.

## VS Code preservation gate (7.1)

Record the actual host/version, installed payload versions and existing settings. The documented
native gap was observed at VS Code 1.141.0; this gate proves preservation on the actual tested target,
not native app-style replacement or unspecified older versions.

Use disposable confirmed fixtures for the existing local/direct and host paths. Invoke `/ci` without
app-native tools and verify current admission, step/phase scope, configured effort/context, Sol
aliases, explicit completion and archive behavior. The `host` selection remains the existing host
launcher, not a global remap to app sessions.

Use a disposable two-child epic with an explicit dependency: the existing host epic wrapper,
per-child provider proof, dependent-child admission and final index archive still work. App local
archive proof must not replace this retained route. Inspect factory repair dispatch/bounds with its
existing approved fixture; this smoke authorizes no production action.

On capable hosts repeat the existing container/Sandbox routes, including human stop/resume, exact
usage/output and bounded rebundle. Capture any unavailable host as incomplete, not a passed test.
Docs must describe native VS Code coordination as deferred; peer chats and inherited settings are
not proof.

## Recorded outcome and rollback

Record in the acceptance conversation the fixture ID, host/client/runtime versions, source/accepted/
worker full heads, app session IDs or owned process/container/session-output identity, observed
settings, actual byte/evidence results, blocker/resume sequence, usage totals, completion/archive
commits, and any authorized final PR URL/base. Redact secrets. A failed or unobservable item keeps
the corresponding implementation human gate pending.

Stop only the identified fixture sessions/processes. Retain commits/worktrees/outputs for inspection;
leave implementation/delivery branches, unrelated environments and credentials unchanged.
Deletion of fixture branches, sessions, containers or output needs separate operator authorization.
