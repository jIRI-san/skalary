# Decisions

Preliminary context captured by /cep; /cip must confirm and refine it.

- **Simplicity is the first rule.** Prefer deletion, direct scripts, and local fixes. When simple and
  safe cannot both be achieved within this trusted single-operator repository, choose the simple
  design and record the tradeoff in the affected design note.
- **No GitHub workflows.** Remove them and their workflow-only support. Do not replace them with
  another hosted pipeline.
- **Whole-suite execution is explicit-only.** Skills and routine scripts must use the smallest
  affected-plugin subset. Only the operator may select the separate full-repository path.
- **Focused timing contract.** Target under 30 seconds per selected command and return a distinct
  timeout result at 60 seconds; one timer owns the directly launched child process tree and returns
  exit `13` (`FocusedTimeout`) after termination. Do not create an aggregate suite gate or recovery
  state.
- **Extend existing focused entry points.** Use `Run-UnitTests.ps1 -TestPath`,
  `Test-Evals.ps1 -Plugin`, and `validate.ps1 -Path`; keep
  `Invoke-WazaEvals.ps1 -Plugin` premium and operator-invoked. Do not add `focus-*` wrappers.
- **Wide execution has one explicit spelling.** Keep `-FullRepository` as the operator-only route and
  remove package aliases or skill instructions that pass it implicitly. Operator-only means direct
  explicit CLI use, not an identity/authentication mechanism.
- **Tests require user value.** Keep only deterministic coverage of current behavior, required
  external formats, or high-impact regressions. Ask the operator about uncertain rows.
- **One temporary ownership inventory.** It classifies all active JSON, gates, tests, notes, and
  contracts once with category counts and reasons; each transfer names a canonical child ID and
  updates that child's references. The inventory is planning evidence, not a new runtime authority or
  permanent parser.
- **Internal formats use strict Markdown.** Keep JSON only where an external consumer requires it.
  Do not add schemas or migrations for retired internal formats.
- **Direct stable scripts.** Read-only and focused scripts may be pre-approved by exact path.
  Mutating scripts remain explicit. Avoid operator-facing module-loading chains and hooks.
- **Cross-host choices are equivalent, not abstracted.** Use native VS Code pickers and a numbered or
  chat CLI equivalent, both with enough context and effort/complexity scores.
- **Bounded prior context.** Reuse the existing bounded artifact adapter instead of creating another
  history service. Current intent and active contracts outrank explicit supersession, which outranks
  older accepted decisions; unresolved conflicts are shown.
- **Flexible cost budget selected by the operator.** Default to 2 agent calls and cap at 5; use a
  primary model plus availability fallback and add reviewers only when justified; load the current
  plan/epic plus at most 5 supporting artifacts; target 600 instruction words and cap at 1,200.
  Record the rationale in a short advisory RFC and use focused consumer fixtures, not a policy engine.
- **Supersedes `31a3ef` Decisions bullets 1-3.** Fast/Slow tiers and mandatory hosted execution no
  longer hold because the operator requires explicit affected-plugin scope and no GitHub workflows.
- **Supersedes `c21cdc` D2-D7 and D13-D17 for repository-owned internal operational formats.**
  Content-addressed JSON, schema authority, manifests, canonicalization, and receipt handshakes are
  not the baseline format. Review-specific removal remains owned by sibling `367e9a`.
- **Rejected:** mandatory CI, Fast/Slow tier machinery, receipt authority, exhaustive review
  matrices, compatibility layers, and reviewer requests to restore platform-scale controls.
- **No unresolved architecture decisions remain.** Test rows that the implementation audit cannot
  classify are an explicit operator disposition gate, not a design decision delegated to execution.
- **Execution defaults to manual, with no new packages.** The test-disposition gate requires operator
  input, and this plan changes repository scripts and documentation only.
- **DR round 1 local fixes accepted; platform expansion rejected.** Physically confine focused paths,
  update each changed format with its producer/consumers, synchronize workflow-authoritative guidance
  with workflow deletion, and bind transfer rows to children. Do not add authentication, transaction,
  receipt, or durable inventory machinery.

## Final review triage

- **Fix direct local regressions only.** Remove the dead architecture sweep, make dependency resolution
  fail loud, keep focused plugin selection confined, reject linked validation descendants, preserve
  useful worker/container diagnostics, remove dead Waza discovery, correct stale architecture-skill
  text, narrow the default test, and add focused evidence for malformed input, empty evals, defaults,
  and public timeout forwarding.
- **Keep the cost RFC as a target, not a false current-state claim.** Existing CR/DR fan-out is a
  transitional exception owned by child `367e9a`; this plan does not rework review orchestration.
- **Defer unrelated pre-existing subsystem issues.** ADR filename collision behavior belongs to the
  architecture-notes subsystem, not this local validation baseline.
- **Reject framework and broad-test expansion.** Do not replace four small local confinement checks
  with a new shared abstraction, add output-streaming infrastructure for trusted focused commands, or
  execute broad operator-only routes as routine evidence. Measured focused commands remain the
  authority for performance; speculative scale concerns do not justify machinery.
- **Accept the documented timeout boundary.** Detached descendant output can be incomplete after a
  timeout; the trusted single-operator threat model does not justify process-group or output-pump
  infrastructure.
- **Final review cycle 2: fix only concrete local regressions.** Run `14711538` produced 26
  single-source findings. Fixed the stale Pester path, current receipt compatibility, structural-only
  report cleanup, required-list parsing, worker diagnostics, Waza environment restoration, resolved
  exploration indexing, focused enumeration, collision-prone test path, automatic-variable use,
  stale hosted-gate wording, bounded process-exit polling, and missing exit-code documentation.
- **Final review cycle 2: reject or transfer the rest.** The configurable harvest test seam and
  plan-local ownership summary remain appropriate in this trusted repository. Additional link and
  exit-code tests are not worth expanding routine coverage. Pre-existing plan-dispatch, container,
  sandbox, transcript, and review-cycle parsing concerns remain with `367e9a`; the pre-existing SI
  diagnostic concern remains with `3a4498`. Missing-origin test setup is unrelated to this plan.
- **Final review cycle 3: close the concrete regression set, then stop.** Run `d5b4c344` reported five
  single-source findings. The focused eval search now starts at each plugin's direct `evals/`
  directory, Waza captures caller token values before resolution and restores them in `finally`, and
  supervisor startup cleanup no longer dereferences an unstarted process. These are local fixes with
  focused coverage. Per the operator's objection to repeated CR execution, do not start a fourth
  review; retain the capped review history instead of extending the loop.
- **Operator-approved archival exception.** On 2026-09-05 the operator explicitly accepted the wrapped
  three-cycle final-review history and directed that the completed plan be archived. This is not clean
  review evidence and does not change the recorded gate result; it is the authority for closing this
  plan without another CR run.
