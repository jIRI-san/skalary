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
- `docs/design-notes/architecture/plan-workflow.design.md`
- `docs/design-notes/architecture/autopilot-execution.design.md`
- `docs/design-notes/architecture/autopilot-skill.design.md`
- `docs/design-notes/architecture/fleet-dispatch.design.md`
- `docs/design-notes/architecture/review-concern-authoring.design.md`
- `docs/design-notes/explorations/agent-cost-optimization.design.md`
- `docs/design-notes/project/design-note-writing-style.design.md`
- `docs/architecture-notes/arch-review-run-v1.md`

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
