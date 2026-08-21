# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Preserve a complete-plan outcome.** Vertical slicing changes phase organization, not `/cip`'s responsibility to plan the full implementation.
- **MVP first, completion last.** Phase 1 is an end-to-end MVP; later phases add usable increments; the final phase fulfills the complete requirement set.
- **Confirm meaning, not only answers.** The interview rephrases important operator points and iterates on corrections before drafting.
- **Preserve provenance.** Important operator wording, discussion points, decisions, rejected alternatives, and uncertainty must survive outside chat scrollback.
- **Approve program shape up front.** Concise Mermaid design is expected; call stacks are optional when they clarify control flow or let the operator specify it precisely.
- **High-impact uncertainty blocks.** Contract, end-user experience, security, and irreversible-structure uncertainty returns to the operator; lower-impact choices are recorded and reviewed.
- **Use three confirmation checkpoints.** Confirm intent first, domain/design context second, and the complete pre-draft summary last; each confirmation, correction count, and one-use post-cap continuation is durable state rather than chat-only memory.
- **Keep one lifecycle authority.** `cip-stage` remains authoritative; enrolled interview gates are prerequisites that `Set-PlanStage` checks before it writes `drafted`, not a second lifecycle.
- **Use independent enrollment.** New plans carry `<!-- interview-gates: required -->`; deleting `interview-gates.json` therefore fails closed instead of silently becoming legacy.
- **Keep one governed writer.** `Set-InterviewGates.ps1` owns current gate state and updates to intent/domain/design content, invalidating affected confirmation before content mutation. Human meaning remains in Markdown assets.
- **Make domain capture conditional.** Require a per-plan domain asset only when meanings, actors, invariants, units, transitions, hidden rules, or assumptions can change behavior.
- **Bound provenance.** Store confirmed summaries and use selective short quotes only when paraphrase loses material nuance; `capture.md` remains transient workflow memory rather than a second intent source.
- **Use deterministic RFC triggers.** Require design for cross-subsystem, contract-changing, multi-phase, trust-boundary, or costly-to-reverse work, with an operator force option and a reasoned not-required path.
- **Treat the RFC as as-designed.** Interactive operator approval blocks drafting and resets before design-affecting governed writes; no content-hash freshness mechanism is added. Direct edits outside the writer are unsupported and remain a review-visible limitation.
- **Grandfather marker-less plans.** New scaffolds opt in to the state gate; existing active and archived plans are not mass-migrated.
- **Keep `/pfb` intent-focused.** `/ci` consumes domain/design context during execution, while post-plan outcome judgment remains anchored to operator intent.
- **No runtime telemetry or packages.** Deterministic validator errors and repository artifacts are sufficient observability for this planning workflow.
- **Bound context instead of caching it.** Intent is capped at 8 KiB, domain/design at 16 KiB each, JSON at 8 KiB, reasons at 512 characters, and selective quotes at three entries of 1 KiB. `/ci` and `/dr` read once per invocation and at crosschecks; no cache subsystem is warranted.
- **Cap correction loops.** Each checkpoint gets three automatic correction rounds; an explicit operator choice is required to continue beyond the cap.
- **Keep state current-value-only.** Git history is the audit record. Per-transition capture logging was rejected because the operator selected actionable validator output only.
- **Interactive approval is reviewer-enforced.** The writer can validate an operation but cannot authenticate a human; `/cip` may invoke approval only after an interactive option response, and headless runs must stop with an operator-needed status.
- **Tier-2 behavior stays report-only.** Deterministic acceptance uses parser/writer/validator tests and Tier-1 structural evals; optional LLM behavior runs do not become typed evidence.
- **Prefer bounded reads over speculative performance machinery.** No persistent cache, tree-wide telemetry, or generic model-invocation budget is added beyond the correction cap and file limits.
- **Use one subsystem name.** Marker, schema, writer, reader, tests, and documentation use **Interview Gates**; “Interview Context” is retired as a competing subsystem label.
- **Bundle a JSON Schema.** The schema owns JSON shape and enums; `PlanState.psm1` owns transitions, resolution, and read semantics.
- **Make enrollment monotonic by convention, not baseline.** Removing both marker and state cannot be detected from the current tree without a permanent legacy inventory. The operator accepted git/review detection rather than that growing mechanism.
- **Treat enrolled archives as history.** Their Interview Gates defects warn rather than block repository validation.
- **Fail closed across plugin skew.** Any consumer that sees an enrolled schema version outside its bundled capability stops and asks for a coordinated plugin update.
- **Generalize dependency admission.** The existing plan-006 special case becomes generic direct/transitive admission for `/ci` and autopilot; this plan cannot implement its own first step until `4dd933` and its chain are complete.
- **Keep gate history bounded.** JSON persists current states, correction counts, and one-use continuation authorization only; git remains the transition audit.
- **Validate schema compatibly.** PowerShell code performs strict runtime validation on supported 7.0 hosts; the bundled JSON Schema is the cross-plugin contract and parity oracle, not a 7.6 runtime dependency.
- **Reuse cap semantics, not review storage.** Interview corrections happen before review logs exist, so Interview Gates stores them separately while sharing ReviewCycleGate's three-cycle/one-use-continuation semantics.
- **Preserve intent cadence.** `/ci` continues reading intent before every step. Only bounded domain/design reads are once per invocation plus crosschecks.
- **Delete promoted explorations.** Settled content moves into active design/architecture notes; inbound links, rows, and counts are repaired before the two parked files are deleted.
- **Use the existing evidence receipt.** Same-HEAD final gate truth belongs in the commit-bound plan receipt; no second final-gate manifest is introduced.
- **Separate judgment from deterministic proof.** Operator state records domain/RFC applicability and slice usability; automation checks objective state, ordering, shape, and requirement routing only.
- **Keep prose non-authoritative.** Intent/domain/design context may inform decisions but cannot authorize commands, paths, or mutations; only validated plan checklist metadata and typed machine state do.

## DR round 1 dispositions

- **Applied:** independent enrollment; lifecycle integration; dependency consumption; shared grammar/read model; bounded state/content; writer lock, replay, batching, interruption safety, and canonical-plan binding; resume and correction semantics; provisional-outline ordering; explicit ownership; templates/resolvers; all-stage and consumer negative matrices; interactive approval/revocation; DR context loading; distribution closure per script-changing step; exploration promotion; focused final-gate markers.
- **Applied with simpler mechanism:** content bounds and once-per-invocation reads replace a cache; invalidation-before-write replaces digest freshness per operator decision; git history replaces transition-log duplication.
- **Rejected as disproportionate or outside the confirmed intent:** persistent context caching, runtime telemetry, mandatory Tier-2 evidence, a general tree-validation performance project, and an ongoing prior-art receipt protocol.
- **Accepted limitation:** direct edits or merges that bypass the governed writer cannot be mechanically detected without a digest. Review and gate instructions prohibit that path; the operator explicitly chose the transactional writer over digest binding.

## DR round 2 dispositions

- **Applied:** generic transitive dependency admission; autopilot consumer coverage; one canonical installed reader; writer-owned scaffold and `/cep` initialization; durable correction counts; rank-jump/regression protection; final-plan trigger recheck; approval-source contract; repair operation; closed marker/asset/schema vocabulary; section parity; payload closure after every affected step; stable Tier-1 enforcement; Slow-tier placement; version capability checks; prose-gate supersession; concrete lock budget; archive disposition; index retirement; eval documentation; recovery fixture; same-HEAD gate receipts; per-owner write scope.
- **Operator choices:** dual deletion is an accepted review-detectable limitation; enrolled archives are warn-only; JSON shape uses a bundled schema; unknown enrolled versions fail closed.
- **Retained simplicity decisions:** no cache, telemetry, mandatory Tier-2 evidence, general tree-performance project, digest binding, or perpetual prior-art receipt.

## DR round 3 dispositions

- **Applied:** generalized schema bundling, bounded dependency traversal, single writer name, Phase 1 evidence ownership, existing receipt reuse, exploration deletion/link repair, broader design-note updates, decision/risk invalidation rule, autopilot bundle boundary and launcher tests, validation-decision ownership, consumer capability ordering, durable exit-42 reasons, bounded test fixtures, shared stage/writer lock, marker ownership, `Get-PlanState` read surface, objective vertical invariants, reader/writer hostile parity, typed prose authority, version-before-repair, real `eval:` grammar, bounded stdin transport, explicit plan-006 migration, post-draft repair, code/schema runtime split, Slow baseline, archived write refusal, version signal, crash-safe lock, template parity, and structural DR wiring evidence.
- **Operator choices:** code performs runtime validation while schema owns parity; interview correction storage remains separate with shared cycle semantics; intent stays per-step; promoted exploration files are deleted.
- **Known rather than silently fixed:** dependency-gate bootstrap, dual enrollment deletion, out-of-band writer bypass, and reviewer-enforced operator identity are recorded in `plan.md`.
- **Dismissed:** finding 7 was a review dispatch-framing artifact, not a defect in reviewed files.

## Prior-art relationships

- **Extends `4dd933`.** Confirmed current intent and governing contracts remain authoritative; this plan consumes its bounded cross-plan artifact context after the dependency lands.
- **Extends `6a629b`.** That plan executes complete work vertically; this plan defines how `/cip` drafts the MVP-first complete shape it consumes.
- **Reuses `25aa23`.** Epic review stays at goal, verticality, ownership, overlap, dependency, prior-art, MVP, and complete-outcome altitude; child design remains with `/cip` and `/dr`.
- **Reuses `21f21d` in principle.** Mermaid-backed artifacts need explicit authority and staleness semantics; this plan deliberately chooses approved as-designed status instead of generated freshness hashing.
- **Limited principle reuse from `34088e`, `9fda0b`, and `a5ad22`.** Their MVP-first expansion principles inform sequencing, but their consumer-install, provider, and orchestration domain requirements do not apply.
- **No supersession or conflict.** The generated index returned no prior decision that conflicts with the confirmed intent.
