# 705e6c: Local-first repository simplification
<!-- epic-id: 705e6c -->
<!-- Folder naming: epics/<yyyy-mm-dd>-<6hex>-<slug> · epic-id is the canonical handle. New-Epic.ps1 fills these in. -->

## Goal

Reduce Skalary to a fast, human-readable, single-operator skill repository by deleting automation
and reliability machinery that costs more than it helps, while retaining focused deterministic
tests, prompt-injection guards, external-format compatibility, and the minimum controls needed to
preserve operator intent within a 200,000 AI-credit monthly ceiling.

**Desired outcome.** Routine skill changes are understandable and quick: agents run only focused
tests for affected plugins unless the operator explicitly requests broader testing; no GitHub
Actions remain; CR/DR and `/si` use small human-readable flows; choices work in VS Code and Copilot
CLI with enough context plus effort and complexity; and `/ci` preserves accepted criteria without
signed receipts. One `/skalary-config` skill explains and safely changes the final configuration
surfaces without becoming a second source of truth.

**Success signals.**

- Repository-owned runtime, state, review, and internal-registry JSON is removed or replaced by
  documented strict Markdown; externally required JSON remains.
- Whole-suite execution is explicit opt-in only, retained tests have a clear value justification,
  and uncertain retention cases are decided by the operator.
- SI/harvest state, repair, CAS, receipt, and remote-lifecycle machinery is removed while
  prompt-injection protection remains.
- CR/DR use direct Markdown reports and materially fewer, strategically selected agent/model calls.
- GitHub workflows are absent and active design guidance prohibits introducing them.
- Planning and review consult bounded prior-plan context using current intent, explicit
  supersession, and recency in that order, surfacing rather than silently applying conflicts.
- Stable direct scripts can be pre-approved and interactive choices expose equivalent context in
  VS Code and Copilot CLI.
- Every shipped configuration uses default context; long context remains only as an explicit
  cost-warned advanced opt-in. Routine work starts with direct tools or inexpensive models, and
  Sol/Opus-class models require an observable escalation reason.
- Planned work targets 180,000 credits monthly with a 20,000-credit incident reserve, without adding
  repository metering or a model-policy service.
- Configuration discovery, bootstrap, editing, reset, synchronization, and focused validation are
  available through one guided skill while every subsystem retains its direct canonical path.

**Non-goals.**

- Converting JSON required by external tools or plugin/package/config interfaces.
- Preserving runtime compatibility or adding migrations for retired internal formats.
- GitHub-hosted CI or support for untrusted third-party contributors and multi-operator coordination.
- Removing prompt-injection guards or weakening the platform's mandatory secret/destructive-action
  protections.
- Rewriting archived historical evidence.

**Definition of done.** Every accepted child ships and reverts independently after its declared
dependencies; active design notes and architecture contracts describe the simplified system; no
prohibited workflow, receipt, or durable repair/state machinery remains; each skill has a small
justified deterministic test set; focused commands and cross-host interactions work; and CR/DR
enforce simplicity while recording any knowingly dubious simple-over-safe decision for later
operator review. The unified configuration skill has focused success/refusal/failure tests and
human-readable documentation for every supported category. Model routing, delegated-call budgets,
premium-eval costs, and skill context are small enough to operate within the stated monthly target.

## Child plans

<!-- child-plans:start -->
| Plan | Slug | Depends on |
|---|---|---|
| `2aa7ec` | local-first-operating-baseline _(archived)_ | — |
| `367e9a` | simple-review-to-plan-workflow _(archived)_ | `2aa7ec` |
| `3a4498` | simple-self-improvement _(archived)_ | `367e9a`, `33a78a` |
| `623cc2` | simple-plugin-lifecycle _(archived)_ | `2aa7ec`, `33a78a` |
| `33a78a` | ai-credit-budget-optimization _(archived)_ | `367e9a` |
| `a524dc` | unified-skalary-configuration _(archived)_ | `367e9a`, `33a78a`, `3a4498`, `623cc2` |
<!-- child-plans:end -->

Membership is the `<!-- epic: 705e6c -->` marker in each child `plan.md`; the table above is a generated
mirror that `New-Epic.ps1` rewrites. Run `Get-PlanState 705e6c` for live rollup and the next unblocked
child plan.

## Decomposition notes

### Accepted children

| Child | Slug | Slice | Done bar | Boundaries and non-overlap | Independent delivery and revert |
|---|---|---|---|---|---|
| `2aa7ec` | `local-first-operating-baseline` | Deliver the repository-wide local operating baseline and simplify all cross-cutting or otherwise unowned validation, metadata, documentation, and tests. | GitHub workflows and coupled workflow-only checks are removed; whole-suite execution is explicit-only; unaffected plugins have direct focused commands that target under 30 seconds and fail distinctly above 60 seconds; each later owner must meet the same bound; every gate, active JSON path, architecture contract, design note, and test file has exactly one keep/transfer/delete owner; the cost RFC ends with operator-approved agent/model/context budgets whose consumers have focused fixtures. | Owns shared mechanisms, global architecture/index retirement, unaffected skills, and repository-wide residue only; each later child owns its subsystem formats, contracts, docs, scripts, and test dispositions. | It leaves a complete locally operable repository and cheap validation path; later children can land or revert independently without hosted CI or a final sweep. |
| `367e9a` | `simple-review-to-plan-workflow` | Replace CR/DR plus `/cip`, `/cep`, `/ci`, autopilot state/evidence, and bounded learning capture as one end-to-end Markdown workflow. | Review input remains fenced and reports remain advisory Markdown with explicit source/scope/completion fields; strategic dispatch follows an operator-approved task/model matrix with OpenAI cost affinity and independent non-OpenAI review coverage; the terminal phase triggers one final CR rather than overlapping post-phase and finalization passes; delegation has bounded progress checks and operator-visible stuck recovery without a scheduler; complex choices include examples, diagrams when useful, pros/cons, effort, complexity, and benefits; `/cip` classifies absolute and fuzzy wording with the operator; security findings require a concrete threat path under the trusted single-operator boundary; confirmed intent/requirements/risks/decisions are immutable during execution while checklist/worktree fields remain mutable resume state; current Git supplies stale checks; `/ci` compacts and deduplicates edited AI-facing design notes once at finalization; `docs/operator-guide/` documents the complete human-facing workflow and is excluded from design-note compaction; one bounded learning-capture output is delivered and the existing SI reader switches to it before ledger/harvest removal, while later proposal selection and writes remain `3a4498`'s responsibility; review/evidence/phase/harvest receipts, review schemas/stores/fleet, generated concern registry, JSON checkpoints, and repair machinery are removed; focused negative tests cover criteria mutation and every retained refusal; subsystem contracts/docs/JSON/tests close in the same child. | Owns the atomic review producer, plan consumer, autonomous execution, delegation policy, human workflow guide, learning-capture producer, and minimal SI input cutover; it does not own SI proposal selection/application or plugin management. | The complete review-to-implementation workflow lands and reverts together, with no intermediate receipt dependency or broken SI/learning interval. |
| `33a78a` | `ai-credit-budget-optimization` | Retune the delivered direct workflow for a 200,000-credit monthly ceiling before the remaining children execute. | Every shipped configuration uses default context while long context remains explicit opt-in; routine implementation/summarization uses Luna, ordinary planning/validation/review uses Terra, Sol is reserved for cross-subsystem orchestration or unresolved diagnosis, and Opus 5 is reserved for one concrete high-risk independent pass or final escalation; automatic second-Judge calls are removed; delegated calls cap at three; Tier-2 eval execution/judging is cheaper and deterministic graders replace LLM graders where observable; high-frequency skills use progressive disclosure; monthly operation targets 180,000 credits with a 20,000 reserve and no metering service. | Owns cross-cutting model bindings, default-first context policy, delegated-call budgets, premium-eval model/grader policy, and recurring skill-context reductions. It does not own SI semantics, plugin lifecycle semantics, or the later configuration facade. | It lands before all remaining children, so their planning and execution use the final budget policy; it can revert independently to the delivered `367e9a` workflow. |
| `3a4498` | `simple-self-improvement` | Replace `/si`, `/pfb`, and proposal harvest with a bounded interactive recent-lessons flow. | `/si` consumes only `367e9a`'s bounded learning output, fences it at read time, shows cited proposals and informed choices, and applies only operator-selected local changes through a physically canonicalized direct path allowlist; agent calls obey `33a78a`'s final cheap-first model ladder and three-call ceiling; durable state, CAS, repair, receipts, remote PR lifecycle, and schemas are removed; workflow paths remain forbidden; subsystem contracts/docs/JSON/tests close in the same child. | Owns proposal harvest and SI/PFB only; learning capture belongs to `367e9a`, and cross-cutting model/call policy belongs to `33a78a`. | After its declared dependencies, SI is a complete guarded workflow and can be reverted without affecting review, plan execution, or plugin maintenance. |
| `623cc2` | `simple-plugin-lifecycle` | Simplify install/update/remove, retirement, registry consumption, and plugin lifecycle tests for a trusted single operator. | Before every write, operations physically canonicalize and confine targets to the consumer `.github` tree; stable direct commands verify resulting manifest-owned paths in memory, fail loudly, distinguish refusal, and converge on unchanged rerun; focused negative tests prove escape/refusal and mutation outcomes; journals, signing/install receipts, CAS, repair, and compatibility machinery are removed; externally consumed plugin/registry/marketplace JSON remains while subsystem contracts/docs/internal JSON/tests close in the same child. | Owns plugin-manager and registry lifecycle behavior only. | Plugin maintenance remains a complete user-facing surface and reverts independently without a later metadata or test sweep. |
| `a524dc` | `unified-skalary-configuration` | Add one `/skalary-config` entry point over the final configuration surfaces delivered by the other children so routine local operation remains understandable without learning every plugin layout. | The skill discovers effective values and precedence; guides show/bootstrap/edit/validate/diff/apply/per-key-reset for autopilot, every `33a78a` model role/primary/fallback/effort/context and waza executor/judge assignment, local review standards, terminal approvals, evals, note scaffolds, and advanced plugin/toolchain policy; writes one category's canonical sources only; shows one secret-redacted diff and confirmation before mutation; invokes existing synchronization and focused validators; preserves unknown fields and unrelated settings; keeps default context for shipped/reset values while requiring a cost-warned advanced choice for long context; and refuses secrets, invalid model combinations, generated copies, runtime state, plan markers, architecture lock promotion, workflows, and auto-approval of mutating or secret-bearing commands. If a write, sync, or validator fails, it stops non-successfully with the remaining Git diff and exact recovery command visible; it claims no rollback. Focused fixtures cover discovery, precedence, lazy bootstrap, cancellation, stale-preview refusal, apply, reset, all model assignments, secret redaction, unsafe-value refusal, failed synchronization/validation, and generated-source discipline; subsystem contracts, docs, manifests, and tests close in the same child. No central config database, replacement schema, receipt, or service is added. | Owns only the configuration catalog and guided façade. Each subsystem retains the meaning, defaults, writer, synchronizer, validator, and direct configuration path for its settings. | Lands after `367e9a`, `33a78a`, `3a4498`, and `623cc2` stabilize final surfaces; can be reverted without removing any underlying direct configuration path. |

| Child | Mechanism | Intent anchor | Owner | Consumers | Demonstrated invariant | Prior-art disposition |
|---|---|---|---|---|---|---|
| `2aa7ec` | Simplicity-first repository principle | Prefer the smallest design for a single-operator skill repository. | `2aa7ec` | `2aa7ec`, `367e9a`, `3a4498`, `623cc2`, `a524dc` | Every child and review uses deletion, reuse, or a local fix before new infrastructure; each affected design note records any dubious simple-over-safe tradeoff in a fixed section. | Reuse `25aa23` proportionality; reject its machinery. |
| `2aa7ec` | Local-only gate disposition and workflow refusal | The operator will not pay for hosted pipelines. | `2aa7ec` | `2aa7ec`, `367e9a`, `3a4498`, `623cc2`, `a524dc` | Workflows are absent; every old workflow gate is explicitly retained as focused, transferred to one child, or deleted; no ordinary command can select a full sweep. | Reject `31a3ef` mandatory CI. |
| `2aa7ec` | Focused per-plugin command contract | Routine changes validate only affected plugins. | `2aa7ec` | `367e9a`, `3a4498`, `623cc2`, `a524dc` | A direct wrapper requires explicit plugin paths, measures each selected command, targets under 30 seconds, returns a distinct timeout result above 60 seconds, and refuses missing scope; `-FullRepository` is a separate explicit operator-only path never called by skills. | Extend `768d7b` focused fail-loud selection; reject tier/budget/profile machinery. |
| `2aa7ec` | Test value disposition by owner | Tests exist only when they protect current value. | `2aa7ec` | `2aa7ec`, `367e9a`, `3a4498`, `623cc2`, `a524dc` | Each child accounts for every in-scope test in a temporary keep/delete/uncertain audit, obtains operator choices for uncertain rows, and maps retained tests to user behavior, an external format, or a high-impact regression. | Reject `31a3ef` complete-tier coverage policy; use `a5ad22` timing evidence. |
| `2aa7ec` | Strict Markdown and JSON ownership convention | Internal operational artifacts must be readable without tooling. | `2aa7ec` | `2aa7ec`, `367e9a`, `3a4498`, `623cc2`, `a524dc` | The completed 80-row baseline inventory is the sole classifier: every active JSON path and invalidated contract/note has one child or fixed external-required disposition, and every later child closes its assigned rows without redefining classification. | Reject `c21cdc` schema-first authority. |
| `2aa7ec` | Cross-host informed-choice contract | VS Code and Copilot CLI must provide equivalent operator context. | `2aa7ec` | `367e9a`, `3a4498`, `623cc2`, `a524dc` | Every consumer has focused host fixtures and supplies context plus `effort: 1-10` and `complexity: 1-10`; complex choices additionally show concrete examples, useful diagrams, benefits, and pros/cons; native pickers have an equivalent numbered/chat CLI path. | Extend existing host behavior without a picker abstraction. |
| `2aa7ec` | Stable direct-script and approval contract | Script calls must be pre-approvable and failures obvious. | `2aa7ec` | `367e9a`, `3a4498`, `623cc2`, `a524dc` | Auto-approval is limited to exact stable paths whose complete transitive behavior only reads repository state and cannot execute repository-controlled hooks, tests, build commands, mutable scripts, or secret-bearing commands; focused runners that execute repository code remain explicit. All scripts use bound arguments, exit `0` only on success, and concise nonzero diagnostics. `a524dc` owns the guided approval surface while each mutating subsystem owns its write confinement. | Extend current direct-invocation guidance without treating a wrapper's filename as proof that its transitive behavior is safe. |
| `2aa7ec` | Bounded historical-context reader | History informs work without overriding current intent. | `2aa7ec` | `2aa7ec`, `367e9a` | One direct read-only command accepts explicit concepts and selected plan IDs, caps index matches/artifacts/bytes, fences and secret-screens content, and returns conflicts without resolving them; the consumer applies current intent/active contracts, explicit supersession, then recency and must show unresolved conflicts. | Extend bounded context from `25aa23`; remove receipt dependencies. |
| `2aa7ec` | Agent-cost RFC and accepted budgets | Reduce repeated context, latency, and token/credit use strategically. | `2aa7ec` | `367e9a`, `33a78a` | The delivered RFC supplies the original call/context/instruction budget; `367e9a` implemented it, and `33a78a` retunes the bindings and limits for the later 200,000-credit ceiling without adding a runtime policy service. | Extend `2366ad` bounded-input principle; revise stale economic assumptions in `33a78a`. |
| `33a78a` | Credit-aware model and context routing | Spend expensive reasoning only where evidence justifies it. | `33a78a` | `33a78a`, `3a4498`, `623cc2`, `a524dc` | No shipped surface selects long context; it remains an explicit cost-warned advanced opt-in. Direct tools and Luna handle routine work, Terra handles ordinary planning/review/validation, Sol and Opus require explicit observable escalation criteria, delegated calls cap at three, and premium evals minimize LLM judging. | Reuse the direct workflow and focused-eval boundaries; replace its pre-cap model defaults and automatic second call. |
| `367e9a` | Fenced advisory Markdown review | Reviews should guide the operator, not authenticate themselves. | `367e9a` | `367e9a` | Reviewed content stays inside the existing data-only fence; fixed report headings name source commit, scope, completed tasks, findings, and verdict; current Git checks freshness; no signature, content address, receipt, or durable authority is claimed. Review security rules retain prompt-injection, secret, destructive-action, external-boundary, and write-confinement checks, but require a concrete attacker/input/capability/impact path before demanding more machinery under the trusted single-operator threat model. | Reject `c21cdc` review-run v1 lifecycle. |
| `367e9a` | Atomic review-to-plan migration | Review producers and plan consumers must never be split. | `367e9a` | `367e9a` | CR/DR, generated concern inputs, `/cip`/`/cep`/`/ci`, autopilot, current plan state, learning capture, docs, JSON, and tests change in one child; focused residue and installed-consumer tests enumerate the closed forbidden old paths and fail if any retired producer, consumer, manifest entry, dogfood copy, or historical-adapter dependency remains. | Reject `c21cdc` receipt authority and `31a3ef` CI coupling. |
| `367e9a` | Single terminal review | The last implementation phase and whole-plan finalization must not review the same effective scope twice. | `367e9a` | `367e9a` | A terminal phase skips the ordinary post-phase pass and runs one whole-plan final CR; non-terminal phases retain only a bounded risk-selected review. Focused fixtures prove one final invocation, bounded retries after corrective changes, and no duplicate model/context fan-out. | Replace the observed `2aa7ec` terminal-phase plus plan-finalization overlap; retain one final whole-plan check. |
| `367e9a` | Instruction-owned delegation and stuck recovery | Human-readable orchestration should replace the PowerShell Fleet scheduler without allowing indefinite waits. | `367e9a` | `367e9a` | `/cip`, `/ci`, autopilot, CR, and DR state dependencies and expected outputs in plain instructions; deterministic scripts remain only for repository facts or focused validation. A delegated task gets one progress inquiry, then bounded cancel/reuse or one replacement call within the cost budget, then explicit operator escalation; repeated output without new evidence counts as no progress. | Remove `FleetDispatch.psm1` and generated attendance machinery; preserve visible failure and dependency ordering. |
| `367e9a` | Precise operator questions | Operators need enough context to make informed decisions and ambiguous policy prose must not masquerade as a contract. | `367e9a` | `367e9a` | Complex questions include context, concrete examples, a diagram when relationships matter, pros/cons, benefits, and 1-10 effort/complexity. `/cip` inventories `always`, `never`, `must`, and equivalent absolutes across active skills/instructions, keeps an absolute only for a confirmed unconditional invariant, otherwise rewrites it as an explicit if-condition/then-behavior/else-or-exception rule and confirms it with the operator. Seeded fuzzy terms such as `detailed`, `thorough`, `robust`, `appropriate`, and `comprehensive` require observable criteria or operator examples. | Extend the informed-choice baseline; use planning clarification rather than a prose linter service. |
| `367e9a` | AI-note compaction and human operator guide | AI context must stay small without making human process documentation terse. | `367e9a` | `367e9a` | If a `/ci` run edits `docs/design-notes/**`, finalization inventories the active index, selects overlapping candidates without loading the corpus wholesale, and processes at most five notes per comparison batch. It preserves unique decisions/contracts/constraints/exceptions/minimal examples, shows the Git diff, requires operator approval before cross-note merge/delete, and updates the index; cancellation or failure leaves the ordinary working-tree diff for correction or Git revert. It never compacts `docs/operator-guide/**`. The operator guide documents `/cip`, `/ci`, CR/DR, autopilot, every artifact, gate, sequence, retry/review limit, stop/resume path, and model-selection rule with Mermaid diagrams. | Extend the existing AI-first writing style; keep human tutorials outside the auto-loaded note tier. |
| `367e9a` | Canonical plan criteria and resume state | Autopilot must preserve operator acceptance criteria without a receipt system. | `367e9a` | `367e9a` | Intent/requirements/risks/decisions are immutable after confirmation; checklist/worktree markers remain mutable; current Git plus those markers drive freshness, stop, resume, and exit; one focused negative test proves criteria mutation is refused before continuation. | Simplify receipt truth to direct prevention and observable comparison. |
| `367e9a` | Bounded learning capture | SI needs useful recent lessons without durable harvest state. | `367e9a` | `367e9a`, `3a4498` | `/ci` or autopilot replaces one bounded cited Markdown artifact and records its source plan/commit; focused producer/consumer fixtures distinguish missing (no completed producer), explicit empty (no lessons), valid, and source-mismatch/stale. Before the review ledger, phase-harvest receipts, overflow, repair, and replay paths are removed, `367e9a` switches the existing SI ingestion boundary to this file and fences it as untrusted; `3a4498` later simplifies proposal selection/application without another input migration. | Simplify workflow-memory and phase-harvest machinery to one local Markdown handoff without a broken consumer interval. |
| `367e9a` | Epic workflow convention ownership | `/cep` and `/ci` need one owner for active epic files, current-child checks, and coherency retirement. | `367e9a` | `367e9a`, `a524dc` | The review-to-plan migration owns active epic format/current-child/coherency behavior and assigns every retired epic review artifact or convention a keep/delete replacement; the later configuration skill may expose only surviving settings and never becomes epic authority. | Keep the useful epic index/ordering behavior; retire review machinery with the workflow that consumes it. |
| `3a4498` | Bounded proposal harvest | SI should help the operator, not operate a durable service. | `3a4498` | `3a4498` | One interactive run reads only `367e9a`'s bounded fenced learning artifact and returns cited proposals without persistent lifecycle state. | Reject `2366ad` durable transport/state expansion. |
| `3a4498` | Prompt-injection and write-scope guard | Harvested text can influence future instructions. | `3a4498` | `3a4498` | Harvested content remains fenced data; the direct scope check uses an explicit allowed-root list and rejects workflow paths; focused negative tests remain. | Reuse `2366ad` untrusted-input guard. |
| `623cc2` | Direct confined plugin lifecycle | Install/update/remove should optimize one trusted operator. | `623cc2` | `623cc2` | Operations physically canonicalize before every write under the consumer `.github` root, refuse manifest-owned `.github/workflows/**`, verify expected manifest-owned paths before success, fail loudly, and converge on unchanged retry; focused negative tests prove escape, workflow, refusal, interruption-visible, and mutation outcomes. | Reject transaction/repair expansion evidenced by `a5ad22`. |
| `623cc2` | External plugin JSON boundary | Required ecosystem interfaces must keep working. | `623cc2` | `623cc2` | `plugin.json`, published registry, and marketplace JSON remain only where external consumers require them; lifecycle-internal state/schema/receipt JSON is deleted or converted locally. | Preserve external contracts; reject internal receipt and repair formats. |
| `a524dc` | Canonical configuration catalog | One entry point must explain where each effective setting comes from without becoming a second source of truth. | `a524dc` | `a524dc` | One human-readable skill asset classifies each final surface by category, canonical/default/generated paths, precedence, bootstrap behavior, sensitivity, writer/synchronizer, and focused validator; unknown or implementation-only surfaces are shown as unsupported rather than guessed. | Reuse direct subsystem writers and the baseline ownership method; reject a registry schema or configuration database. |
| `a524dc` | Guided configuration transaction | The operator should see the complete intended change before any canonical source changes. | `a524dc` | `a524dc` | Discovery and proposal are read-only and secret-redacted; one Apply/Cancel checkpoint precedes writes; one category-scoped apply changes canonical sources only, preserves unknown fields/unrelated settings, runs required existing synchronization, and reports the final focused validation and diff. A failed write/sync/check stops non-successfully and shows the remaining Git diff plus the direct recovery command; it never claims rollback. Reset is per-key/per-surface and derives defaults from shipped examples. | Compose existing bootstrap, validation, sync, registry, and approval scripts; do not reimplement their semantics. |
| `a524dc` | Configuration safety boundary | Secrets, executable commands, generated files, and policy authority require distinct handling. | `a524dc` | `a524dc` | The skill reports credential availability without values; never manages plan/runtime state or generated copies directly; refuses workflow creation and architecture lock promotion; requires explicit confirmation for executable autopilot values; and exposes manifests, allowlists, eval pins, and toolchain policy only through a clearly labeled advanced path. | Preserve the trusted-operator threat model while retaining secret, destructive-action, external-format, and write-confinement controls. |

### Direct dependencies

| Dependent child | Prerequisite | Prerequisite-delivered behavior that is required |
|---|---|---|
| `2aa7ec` | _(independent)_ | Establishes the complete local operating baseline, focused validation, ownership inventory, and shared conventions without another child. |
| `367e9a` | `2aa7ec` | Needs focused commands, accepted agent budgets, Markdown/history/choice/script rules, and explicit review/plan JSON ownership before replacing the full workflow. |
| `33a78a` | `367e9a` | Needs the delivered direct review/planning/autopilot surfaces before making default context universal and retuning their model, call, eval, and skill-context policies. |
| `3a4498` | `367e9a`, `33a78a` | Needs the delivered bounded fenced learning-capture artifact plus the final credit-aware model/call policy before replacing proposal harvest. |
| `623cc2` | `2aa7ec`, `33a78a` | Needs focused commands, external-JSON classification, direct-script rules, and the final premium-eval model/grader policy before deleting plugin machinery. |
| `a524dc` | `367e9a` | Needs final model/review/autopilot configuration surfaces before exposing them through one façade. |
| `a524dc` | `33a78a` | Needs the default-context-only rule, final model ladder, and monthly budget guidance before exposing model and autopilot settings. |
| `a524dc` | `3a4498` | Needs the final SI/PFB configuration and refusal surface so runtime lifecycle state is not misclassified as user configuration. |
| `a524dc` | `623cc2` | Needs final plugin manifest, registry, marketplace, and lifecycle synchronization behavior before offering advanced plugin configuration. |

### Delivery routes

**Usable MVP.** `2aa7ec` immediately removes GitHub workflows, establishes the simplicity and
single-operator contract, supplies focused local commands under the 60-second bound, and records the
operator-approved cost RFC so every later child can work cheaply.

**MVP to final.** From that baseline, `367e9a` delivers the simple review-to-plan outcome and its
bounded learning handoff. `33a78a` then makes default context universal while retaining explicit
long-context opt-in, and retunes calls, models, premium evals, and recurring skill context for the
200,000-credit ceiling. `3a4498` and `623cc2` proceed under that
final budget policy to close SI and plugin lifecycle. After those subsystem owners stabilize their
direct configuration paths, `a524dc` adds the unified guided façade without changing their semantics.
Completion of those routes satisfies the whole-epic done bar without a horizontal sweep.

### Prior art

| Candidate | Disposition | Owning child | Rationale |
|---|---|---|---|
| `2366ad` | reuse | `3a4498` | Retain untrusted-input treatment for harvested text; reject durable typed transport and lifecycle assumptions under the accepted single-operator boundary. |
| `25aa23` | reuse | `367e9a` | Retain proportionality and concrete simplify/defer decisions; do not retain fixed fourteen-task review, verdict JSON, or receipt authority. |
| `31a3ef` | reject | `2aa7ec` | Mandatory Fast/Slow CI and complete-tier coverage directly conflict with explicit-only whole-suite execution and no GitHub workflows. |
| `768d7b` | extend | `2aa7ec` | Keep focused fail-loud selection, but replace runtime ceilings, tier manifests, profiles, and workflow enforcement with direct plugin commands and later value-based pruning. |
| `a5ad22` | reuse | `2aa7ec` | Its 76-minute profile and 14-hour orchestration record are the accepted performance baseline and identify the highest-value owner-local audit targets. |
| `c21cdc` | reject | `367e9a` | Content-addressed JSON, schemas, frozen stores, manifests, canonicalization, and compact signed receipts are the review complexity this epic removes atomically with plan consumers. |
| `9fc66d` | extend | `a524dc` | Reuse direct plugin-manager commands, canonical-source ownership, terminal approvals, and generated-catalog sequencing behind one guided façade; do not introduce a second lifecycle or configuration authority. |

## Epic coherency verdict

<!-- epic-coherency-verdict:start -->
Schema: `skalary/epic-coherency-verdict@1`
Prior source digest: `sha256:fa6babdb3cc5f114eeb4f40f2d21fc1136d6cfed3d28356b0db9f64e62e519ce`
Review run: `5109525f-9787-4367-b1b1-3a1419ba8b40`
Operator decision: **simplify**
Blocking: **no**
Action: Operator retained the five-child cut, accepted bounded local fixes for naming, compaction, configuration failure handling, SI budgets/confinement, learning states, ledger ownership, and prior art, and rejected or deferred the remaining uncorroborated demands for additional authority, rollback, or ownership machinery.

| Task ID | Finding title | Proportionality class | Blocking | Operator decision | Concrete action |
|---|---|---|---|---|---|
| _(none)_ | | | | | |
<!-- epic-coherency-verdict:end -->
