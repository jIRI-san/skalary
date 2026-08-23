# Decisions

- **Review the accepted cut before finalization.** `/cep` invokes coherency review after operator acceptance and before scaffolding/finalizing children.
- **Use existing review-run v1.** Existing design-review agents, fixed concerns, dispatch planner, publication, and verification remain authoritative.
- **Fix the scope.** Coherency covers goal/done coverage, verticality, child independence/overlap, ownership, necessary acyclic dependencies, MVP/final route, and prior-art reuse.
- **Make proportionality explicit.** Findings are classified as local fix, required shared contract, or speculative platform.
- **Require demonstrated invariants.** Shared architecture is justified only by a concrete invariant spanning children; a minor/local finding cannot create a schema, protocol, store, state machine, compatibility layer, provider, or dependency.
- **Challenge every mechanism and edge.** Compare proposed machinery to confirmed operator intent, detect duplication, require one owner, and reject infrastructure-only dependencies.
- **Prefer smaller outcomes.** Review decisions are concrete `keep`, `simplify`, `split`, or `defer` actions, favoring deletion, reuse, and local fixes.
- **Keep operator authority.** `/cep` cannot finalize an overcomplicated cut until blocking findings are resolved by the operator.
- **Store one compact result.** A marker-managed verdict and resolution section lives with the epic; it is not a second review authority or lifecycle.
- **Recheck before execution.** Apply the same rubric to the current child plan and graph before every epic child run because review rounds or later edits can reintroduce unnecessary machinery after the cut was approved.
- **Do not build a pre-run subsystem.** Record `keep`, `simplify`, `split`, or `defer` in the existing epic verdict or plan decisions and use Git history; no schema, receipt, cache, lifecycle, or separate state file is justified.
- **Reject prior expansion.** No RFC/state schemas, epic review authority, `review-concerns@2`, generated CEP concern family, dormant APIs, write-ahead orchestration, activation transaction, repair protocol, or new architecture contract is part of this plan.

## Simplification decision

The accepted cut directly addresses the observed failure mode: repeated review of local findings must not manufacture durable infrastructure. Existing review execution plus a strict proportionality rubric and compact operator-resolved verdict are sufficient.
