# References

Preliminary context captured by /cep; /cip must confirm and refine it.

## Epic and dependency

- Epic `705e6c`: `docs/implementation-plans/epics/2026-09-03-705e6c-local-first-repository-simplification/epic.md`
- Depends on `2aa7ec` for focused commands, format ownership, informed choices, bounded history, and
  accepted cost budgets.
- Implements `docs/design-notes/explorations/agent-cost-optimization.design.md` across this child's
  agent surfaces and extends it with task/model economics: routine OpenAI affinity from the operator's
  subscription and strategically selected non-OpenAI review.
- Transferred rows are enumerated in
  `docs/implementation-plans/705e6c-2026-09-03-2aa7ec-local-first-operating-baseline/assets/ownership.md`;
  `367e9a` owns every row carrying that owner id.
- Produces the bounded learning artifact consumed by `3a4498`.

## Accepted prior-art provenance

| Source | Disposition | Use here |
|---|---|---|
| `25aa23` | Partial reuse | Keep proportionality and explicit operator decisions; remove fixed review machinery. |
| `31a3ef` | Reject | Remove CI coupling and suite-tier enforcement. |
| `c21cdc` | Reject mechanism | Remove review-run JSON, schemas, manifests, canonicalization, and receipts while retaining data fencing and secret handling where needed. |
| `2366ad` | Partial reuse | Keep bounded untrusted learning input; reject durable transport and lifecycle state. |

## Relevant repository guidance

- `docs/design-notes/architecture/review-reporting.design.md`
- `docs/design-notes/architecture/direct-workflow-core.design.md`
- `docs/design-notes/architecture/plan-workflow.design.md`
- `docs/design-notes/architecture/autopilot-execution.design.md`
- `docs/design-notes/architecture/self-improvement.design.md`
- `docs/design-notes/architecture/plugin-registry.design.md`
- `docs/design-notes/explorations/agent-cost-optimization.design.md`
- `docs/design-notes/project/design-note-writing-style.design.md`
- `docs/architecture-notes/arch-direct-workflow.md`
- Historical predecessor: `docs/architecture-notes/archives/arch-review-run-v1.md`

## Epic discussion provenance

On 2026-09-03 the operator said repeated DR/CR rounds turn simple designs into architectural
astronautics, consume too many agents and context reloads, and ask questions without enough context.
They required simplicity to constrain review, informed choices to include effort and complexity,
criteria preservation without signed receipts, bounded prior-plan lookup, and equivalent VS Code/CLI
operation. They later read and accepted the four-child plan and directed that review demands which
restore platform complexity be removed rather than propagated.

On 2026-09-05 the operator added: compact and deduplicate edited design notes at `/ci` finalization;
make complex questions decision-ready with examples, diagrams, tradeoffs, estimates, and benefits;
audit absolute/fuzzy instruction language and confirm its meaning; detect stuck tasks/subagents;
replace script-orchestrated role dispatch with plain instructions if it still exists; define concrete
proportional security-review rules; extend the model-cost work with OpenAI affinity plus independent
non-OpenAI review; publish complete human workflow documentation under the selected
`docs/operator-guide/`; and prioritize removal of overlapping terminal/final CR work observed during
the completed `2aa7ec` run.

The operator then confirmed OpenAI-first routine work with Claude limited to final or concrete high-risk
review; progress-only agent stuck detection with two evidence-free checks; retained deterministic
command timeouts; the absolute/fuzzy vocabulary and if/then rule; the concrete proportional-security
rules; conditional design-note compaction with approval for cross-note merge/delete; stage-specific
review reports plus `final.md`; `docs/feedback/recent-learning.md` at 10 items/16 KiB; and an operator
guide split into README, planning, implementation, and reviews.

## Step 5.1 compaction preparation

`Get-DesignNoteCompactionContext.ps1` was run against the current criteria baseline
`a652134251e217e8227e184dae1bf49a32b294df`. It returned `ShouldRun: true` and three sequential
candidate batches:

1. `architecture-notes`, `autopilot-execution`, `autopilot-skill`, `direct-workflow-core`, and
   `plan-workflow`;
2. `plugin-manager`, `plugin-registry`, `review-reporting`, `self-improvement`, and the resolved
   `si-cross-repo-proposal-protocol` exploration;
3. `copilot-customizations`, `design-note-writing-style`, and `dev-rules`.

The notes retain distinct owners, but the first two batches contain repeated direct-workflow and
distribution explanations; the resolved SI exploration is the only plausible archive/merge candidate.
No cross-note merge or deletion was performed in Step 5.1. Step 5.3 must rerun discovery after Step 5.2
and execute the plan's one final compaction pass, with operator approval for any cross-note merge/delete.

## Step 5.2 residue disposition

The 25-candidate Step 5.1 residue pass was rechecked against active manifests, canonical scripts,
plugin sources, and installed `.github` payloads. The obsolete plan-006 compatibility preflight was
deleted from its canonical source, CI/autopilot bundles, dogfood copies, manifest entries, launcher
hook, and test. The retired diff-extraction suite was also deleted. Retained tests were narrowed to
current direct intent, plan validation, script bundling, consumer installation, and external-format
behavior; retired schema/ledger fixtures and assertions were removed from those tests.

The historical adapter still reads only confined Markdown and imports `PlanState.psm1`,
`SecretGuard.psm1`, and `DirectWorkflow.psm1`. The closed residue test independently scans the five
direct source plugins and a manifest-built installed `.github` tree. SI proposal state/receipts owned
by `3a4498`, plugin installation/retirement receipts and frozen fixtures owned by `623cc2`, legacy plan
asset mappings, host/container/Sandbox configuration, published registries, and archived history were
retained.

## Step 5.3 compaction evidence

On 2026-09-05 the operator approved all within-note proposals from three read-only reviews and the
cross-note merge/delete described in [decisions.md](decisions.md). Execution used the approved three
sequential batches (five notes maximum); `self-improvement.design.md` was read and retained unchanged.

| Batch | Note | Before (lines/bytes) | After (lines/bytes) |
|---|---|---:|---:|
| 1 | `architecture-notes.design.md` | 86 / 6,088 | 48 / 2,964 |
| 1 | `autopilot-execution.design.md` | 44 / 2,732 | 42 / 2,575 |
| 1 | `autopilot-skill.design.md` | 24 / 1,197 | deleted / 0 |
| 1 | `direct-workflow-core.design.md` | 39 / 2,905 | 34 / 2,407 |
| 1 | `plan-workflow.design.md` | 73 / 4,675 | 54 / 3,218 |
| 2 | `plugin-manager.design.md` | 76 / 7,209 | 56 / 2,995 |
| 2 | `plugin-registry.design.md` | 318 / 28,956 | 145 / 9,530 |
| 2 | `review-reporting.design.md` | 55 / 3,459 | 45 / 2,602 |
| 2 | `self-improvement.design.md` | 25 / 1,291 | 25 / 1,291 |
| 2 | `si-cross-repo-proposal-protocol.design.md` | 181 / 11,189 | 48 / 3,121 |
| 3 | `copilot-customizations.design.md` | 59 / 3,189 | 43 / 2,364 |
| 3 | `design-note-writing-style.design.md` | 111 / 4,434 | 57 / 2,153 |
| 3 | `dev-rules.design.md` | 63 / 4,940 | 40 / 2,119 |
| **Total** | **13 selected notes** | **1,154 / 82,264** | **637 / 37,339** |

Net reduction is 517 lines and 44,925 UTF-8 bytes. Related ownership links moved duplicated
distribution completion detail to `plugin-registry.design.md`, unit/Pester policy to
`ci-gates.design.md`, and structural-eval policy to `plugin-evals.design.md`.

Focused verification covered 34 design-note/direct-workflow Pester cases; 22 structural eval cases for
design-notes, plugin-manager, autopilot, CI, CR, and DR; architecture-doc freshness; registry validation;
bundle/marketplace/dogfood drift; and both direct plan validators. All passed. The separately attempted
architecture-notes structural suite passed 28/30; its two stale cases reference
`drafting-guide.md`/`crosscheck-guide.md`, files already absent at baseline commit `0bd708e`, so this
compaction does not widen into that pre-existing test repair.
