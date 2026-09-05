# Operator guide

## Purpose and audience

This guide explains the active Skalary plan workflow to its single human operator. It is a tutorial
and operating reference, not agent policy. Executable skills, scripts, schemas, and Git remain the
sources of truth; links below point to them.

## Start here

| Goal | Route | Guide |
|---|---|---|
| Split a large goal into independently executable plans | `/cep` | [Planning](planning.md) |
| Create or repair one confirmed plan | `/cip` | [Planning](planning.md) |
| Continue a plan interactively or choose autonomous execution | `/ci` | [Implementation](implementation.md) |
| Review code or a design | `/cr` or `/dr` | [Reviews](reviews.md) |

## Artifact catalog

“Owner” means the workflow allowed to create or replace the artifact. “Source of truth” identifies
what wins when prose and executable state disagree.

| Artifact | Owner | Location | Lifecycle and mutability | Source of truth | Consumer |
|---|---|---|---|---|---|
| Epic index | `/cep` | [`docs/implementation-plans/epics/`](../implementation-plans/epics/) | Created after epic-cut confirmation; its table is a generated mirror | Child plan `epic:`/`depends-on:` markers for membership/order; committed `epic.md` for epic identity | Operator, later `/cip` |
| Plan index and progress | `/cip`, then `/ci`/autopilot | [`docs/implementation-plans/<plan>/plan.md`](../implementation-plans/) | Identity and confirmation marker are planning-owned; checklist, stage, and worktree markers stay mutable during execution | Current Git tree plus plan parser | `/ci`, autopilot, validators |
| Intent | `/cip` | `assets/intent.md` in the plan | Confirmed before drafting; immutable during execution unless planning is reopened | Confirmation-baseline Git tree | Admission and implementation |
| Domain model | `/cip` | `assets/domain.md` | Planning context; revise through `/cip` | Current committed file | Designer, implementer, DR |
| Approved design | `/cip` | `assets/design.md` | Confirmed design context; revise through `/cip` | Current committed file | Implementer and DR |
| Requirements | `/cip` | `assets/requirements.md` | Confirmed criteria; byte-protected during execution | Confirmation-baseline Git tree | `/ci`, evidence |
| Risks | `/cip` | `assets/risks.md` | Confirmed criteria; byte-protected during execution | Confirmation-baseline Git tree | Review selection |
| Decisions | `/cip` | `assets/decisions.md` and optional `assets/decisions/*.md` | Confirmed criteria; byte-protected during execution | Confirmation-baseline Git tree | All later stages |
| References | `/cep` or `/cip` | `assets/references.md` | Accepted provenance; may be refreshed through planning | Current committed file | Planning and review |
| Architecture contracts | Human-owned architecture flow | [`docs/architecture-notes/`](../architecture-notes/) | Active contracts; changed with their boundary | [Architecture index](../architecture-notes/.architecture-notes.md) | Planning, implementation, review |
| AI design notes | Implementer/design-note flow | [`docs/design-notes/`](../design-notes/) | Updated with implementation; conditionally compacted at whole-plan finalization | [Design-note index](../design-notes/.design-notes.md) | Agents working in matching scope |
| Local review standards | Repository operator | `docs/review-standards.md`, when present | Optional bounded Markdown; editable local policy | Base review guards plus [`Resolve-DirectReviewStandards`](../../scripts/skalary/DirectWorkflow.psm1) | CR and DR |
| Phase/final review report | CR or DR orchestrator | `assets/reviews/phase-<N>.md` or `assets/reviews/final.md` | Replaced only after changed-scope correction; advisory history | Active in-memory review result for evidence; report for history | Operator and historical-context adapter |
| Current evidence | `/ci` or autopilot | Current command result, current file, active in-memory review | Exists only for the active crosscheck | [`Invoke-DirectEvidence`](../../scripts/skalary/DirectWorkflow.psm1) inputs | Phase/plan close |
| Recent-learning handoff | `/ci` or autopilot | [`docs/feedback/recent-learning.md`](../feedback/recent-learning.md) | Atomically replaced after successful whole-plan source commit; never appended | [`Write-RecentLearning.ps1`](../../scripts/skalary/Write-RecentLearning.ps1) validation | `/si` |
| Autonomous configuration | Operator and `/ci` | `.autopilot.json`; optional `.autopilot.host.json` | Host-local, validated before launch; not plan criteria | [Autopilot schemas](../../plugins/autopilot/schemas/) and launcher | Autopilot launcher |
| Baseline and progress history | Git plus executor | Git commits | Confirmation commit is immutable history; completed work is committed step-by-step | Git object database | Criteria baseline, resume, rollback |

The plan layout and marker grammar are defined by
[`plan-workflow.design.md`](../design-notes/architecture/plan-workflow.design.md) and
[`PlanState.psm1`](../../scripts/skalary/PlanState.psm1).

## Gates and stops

| Point | Pass condition | Stop/outcome | Resume |
|---|---|---|---|
| Intent and epic cut | Operator confirms the current goal/cut | Planning remains open | Answer the focused question |
| Language gate | Absolutes are confirmed invariants or conditional rules; fuzzy terms are observable | No draft | Clarify through `/cep` or `/cip` |
| Final planning confirmation | Intent, requirements, risks, and decisions confirmed together | No `planning-confirmed` marker | Revise and reconfirm in `/cip` |
| Plan validation/admission | Plan structure, dependency, and stage are valid | `refused` or `blocked` | Fix planning/dependency state |
| Git criteria baseline | Unique marker-introducing commit; four criteria files match through Git clean filters and are committed | `refused`, operator action (`42` in autonomous mode) | Return to `/cip`; commit a new confirmation |
| Runtime preflight | Config, auth, branch, host/container/sandbox requirements pass | Nonzero failure | Correct the named prerequisite |
| Focused validation | Selected command completes successfully | `blocked`/failure; timeout is command evidence | Fix and rerun the same focused scope |
| Direct evidence | Every `test:`, `file:`, and `review:` marker passes current evidence | Phase cannot close | Produce current evidence |
| Non-terminal review | Concrete risk selects review and result is resolved | `findings` or `incomplete` | Correct source, then replace the report |
| Design-note compaction | Triggered only by changed `docs/design-notes/**`; semantic checks pass | Cross-note merge/delete needs operator action (`42` headlessly) | Apply/cancel the visible proposal |
| Terminal review | One whole-plan event is complete and clean | `findings` or `incomplete`; no completion | Correct changed scope, validate, replace final report |
| Learning handoff | Completed source commit and bounded cited content validate | Completion is not claimed | Correct input and replace the handoff |
| Completion/archive | All steps checked, evidence clean, learning committed | `completed` (`0`) | Archive the completed plan when the active flow directs it |

## Global limits and budgets

| Limit | Active value | Authority |
|---|---:|---|
| Monthly AI credits | 180,000 operating; 20,000 reserve; 200,000 ceiling | [Agent cost policy](../design-notes/explorations/agent-cost-optimization.design.md) |
| Delegated calls | 0 for direct work; 1 for a concrete unresolved concern; 3 maximum, including retries and replacements | [Agent cost policy](../design-notes/explorations/agent-cost-optimization.design.md) |
| Supporting historical artifacts | At most 3 | [Direct workflow architecture](../architecture-notes/arch-direct-workflow.md) |
| Delegated prompt | 400-word target; 800-word hard cap | [Agent cost policy](../design-notes/explorations/agent-cost-optimization.design.md) |
| Model ladder | Luna routine; Terra standard; Sol deep; Opus independent; host-default context only | [Agent cost policy](../design-notes/explorations/agent-cost-optimization.design.md) |
| Observable stuck recovery | 2 no-progress checks, 1 redirect, at most 1 replacement | [`/ci` skill](../../plugins/continue-implementation/skills/ci/SKILL.md) |
| Non-terminal review | Only on concrete risk; 1 event plus at most 1 changed-scope replacement | [Review design](../design-notes/architecture/review-reporting.design.md) |
| Terminal review | Exactly 1 whole-plan review event | [Direct workflow contract](../architecture-notes/arch-direct-workflow.md) |
| Design-note comparison | At most 5 full notes per sequential batch | [Compaction protocol](../../plugins/autopilot/skills/autopilot/assets/design-note-compaction.md) |
| Recent learning | At most 10 cited items; 16 KiB UTF-8 | [Self-improvement design](../design-notes/architecture/self-improvement.design.md) |
| Focused commands | 30-second target; 60-second default deadline | [CI gates](../design-notes/project/ci-gates.design.md) |

The pricing snapshot is dated **2026-09-05**. Check the
[official model pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
and [AI-usage guidance](https://docs.github.com/en/copilot/tutorials/optimize-ai-usage) weekly against
actual model-level usage. The
[workflow recommendations](https://movarnell.github.io/Copilot-Links/models.html#workflow-flows) are
non-authoritative. Static instructions guide spend; they do not enforce the monthly ceiling.

## Documentation boundary

`docs/operator-guide/**` is human-facing, is not auto-loaded through either design-note index, and
**design-note compaction does not apply here**. Guide-only changes neither trigger nor participate in
compaction. Keep this guide linked to active sources rather than copying large implementation details.

Retired workflow contracts remain only as non-indexed history under
[`docs/architecture-notes/archives/`](../architecture-notes/archives/). Archived plans and evidence
remain historical records and never become active authority.
