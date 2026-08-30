# Decisions

- **Materialize only the epic before review.** After operator acceptance, `/cep` creates or updates
  canonical `epic.md` with the complete accepted cut and provisional compact decision. It does not
  scaffold child folders until coherency review passes.
- **Use exact-source review-run v1 authority.** Existing design-review agents, fixed concerns,
  dispatch planner, publication, and verified readers remain authoritative. The installed `/dr`
  lifecycle freezes the one canonical epic path, fixed `modified` path status, exact-byte source
  digest, fixed scope, and full task matrix. Freeze, dispatch, publication, reader, timeout, model,
  or attendance degradation blocks.
- **Do not ingest sibling bodies.** The canonical epic source contains all review input. `/cep`
  passes one immutable secret-screened, untrusted envelope to every reviewer and never assembles
  authority from child plans or related-plan content.
- **Fix the scope.** Coherency covers goal/done coverage, verticality, child independence/overlap, ownership, necessary acyclic dependencies, MVP/final route, and prior-art reuse.
- **Make proportionality explicit.** Findings are classified as local fix, required shared contract, or speculative platform.
- **Require demonstrated invariants.** Shared architecture is justified only by a concrete invariant spanning children; a minor/local finding cannot create a schema, protocol, store, state machine, compatibility layer, provider, or dependency.
- **Challenge every mechanism and edge.** Compare proposed machinery to confirmed operator intent, detect duplication, require one owner, and reject infrastructure-only dependencies.
- **Prefer smaller outcomes.** Review decisions are concrete `keep`, `simplify`, `split`, or `defer` actions, favoring deletion, reuse, and local fixes.
- **Keep operator authority without self-attestation.** `/cep` returns every decision-changing
  finding to the interactive operator. Headless execution cannot resolve or waive it. Editable prose
  records the decision but never proves authorization or review success.
- **Use one existing writer and rerun after edits.** Extend confined `New-Epic.ps1` to replace one
  bounded verdict/resolution block atomically after checking the prior source digest and marker
  shape. Seed the provisional cut decision before the first review. Resolution rows bind the exact
  verified finding task id and title, one proportionality class, blocking state, operator decision,
  and concrete action. Duplicate, missing, conflicting, unbalanced, linked, stale, or out-of-scope
  writes fail before mutation.
- **Final clean review performs no write.** Any `simplify`, `split`, or other resolution that changes
  canonical bytes invalidates the prior run and requires reconfirmation plus a new ordinary review.
  Finalization requires a published, verified, finding-free run with complete attendance bound to
  current bytes; it must not mutate `epic.md` afterward.
- **Recheck before execution.** After normal `/ci` admission, apply the same rubric to the current
  child plan plus `Get-EpicRollup` and existing epic verdict metadata. Do not read sibling plan
  bodies. Use the verified epic source digest and Git history as the baseline.
- **Do not build a pre-run subsystem.** The prompt-level semantic check is subordinate to existing
  deterministic admission. Record `keep`, `simplify`, `split`, or `defer` in the existing epic
  verdict or current-plan decisions; unresolved findings stop interactive and headless runs. No
  schema, receipt, cache, lifecycle, or separate state file is justified.
- **Synchronize payloads with implementation.** Every source skill edit updates its installed copy
  in the same implementing step. Phase 3 proves final source/install/catalog drift absence rather
  than repairing accumulated drift.
- **Reject prior expansion.** No RFC/state schemas, epic review authority, `review-concerns@2`, generated CEP concern family, dormant APIs, write-ahead orchestration, activation transaction, repair protocol, or new architecture contract is part of this plan.

## Simplification decision

The accepted cut directly addresses the observed failure mode: repeated review of local findings must not manufacture durable infrastructure. Existing review execution plus a strict proportionality rubric and compact operator-resolved verdict are sufficient.
