# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Review the accepted cut before finalization.** The operator still confirms the proposed cut first; coherency review then tests it independently before child drafting proceeds.
- **Scaffold only the epic before review.** No child folder exists until the reviewed cut is clean and confirmed.
- **Use a stable decomposition RFC as the source.** `decomposition.rfc.md` carries the proposed cut, complete child context, prior-art snapshot, and index errors under the existing v1 `rfc` kind; rejected after DR: binding mutable `epic.md`, whose generated table and retained evidence would invalidate its own digest.
- **Make the RFC structured and script-owned.** `skalary/epic-decomposition@1` canonical JSON is embedded in deterministic Markdown; a writer validates and scans before persistence, and the scaffolder consumes the same closed object rather than parsing prose.
- **Bound the RFC and operation.** At most 64 children, 512 edges, 1,024 prior records/errors, 256 KiB RFC bytes, six rounds, 48 tasks, 96 attempts, and six retained pairs keep review and resume finite.
- **Review epic shape, not child implementation.** Goal coverage, verticality, ownership, overlap, dependencies, prior art, MVP, and complete outcome are in scope; child requirements and code design remain with `/cip` and `/dr`.
- **Reuse the shared fleet.** Epic review follows `8a0644`'s four-in-flight cap, waves, attendance, and degradation contract instead of adding another scheduler.
- **Use four epic-specific concerns across two configured models.** Coverage/delivery, slice executability, ownership/overlap, and dependencies/prior art form eight independent tasks in two waves; rejected: the seven generic DR concerns and a single-model run.
- **Version concern authorship as `review-concerns@2`.** Preserve `79cfe1`'s seven CR/DR ids and bytes, add a family/applicability axis with exactly four CEP coherency ids, and keep one registry/template/inventory/generator path.
- **Add first-class epic-associated review-run authority.** `-EpicDir` resolves through epic inventory and owns confined live/retained storage while keeping v1 schemas unchanged; rejected after DR: generic cleanup plus a prompt-authored epic note, which cannot preserve verifiable authority.
- **Make source and lifecycle checks script-owned.** The engine reads/scans/hashes RFC bytes; a schema-validated helper owns durable rounds, dispositions, confirmation, retained identities, and resumable scaffold progress.
- **Resolve every epic review asset centrally.** `Resolve-EpicAssetPath` owns RFC, state, run, retained, and cleanup locations and round-trips epic identity before any read or write.
- **Reuse review-cycle policy.** Extract the pure three-cycle/one-grant transition logic used by `ReviewCycleGate.ps1`; epic state adds persistence and operation bounds but not a second cycle policy.
- **Block on degraded attendance.** Any failed, timed-out, omitted, cancelled, malformed, or unverifiable task prevents finalization; the operator cannot waive an incomplete run in this plan.
- **Bound iteration at three automatic rounds.** Every source revision invalidates the previous verdict and triggers a full rerun; unresolved findings after round three return control to the operator.
- **Count rounds across revisions.** One operation id survives digest changes; every frozen fleet dispatch consumes a round, while the scheduler's one typed throttle retry remains an attempt inside that round.
- **Do not invent timeout control.** Reuse `8a0644`'s typed host timeout outcome; the scheduler records it and blocks the run but cannot terminate an unresponsive VS Code host call.
- **Decision-changing findings return to the operator.** Clear defects revise the cut; agent review never silently overrides an accepted product boundary.
- **Reconfirm every revised cut.** Any review-driven edit requires operator acceptance before children are scaffolded, including edits classified as clear defects.
- **Retain every round and finalize before cleanup.** Superseded rounds remain blocked retained pairs; the approved round and bounded disposition state are verified before live cleanup or child creation.
- **Scaffold through an idempotent confined helper.** Deterministic work — context transfer, child/edge writes, resume, and parity — belongs to a script, not prompt prose.
- **Compose existing structure writers.** The helper calls `New-Plan.ps1` and `New-Epic.ps1`; it does not own folders, membership markers, dependency markers, or the generated table.
- **Keep existing children immutable during extension.** The synchronizer may create children for the current operation but never overwrites a child already handed to `/cip`; unsafe partial output is preserved and diagnosed unless it is an unchanged operation-owned scaffold eligible for rollback.
- **Publish degradation, do not hide it.** Every terminal task set publishes through v1; non-complete attendance finalizes as blocked retained evidence and consumes a round.
- **Activate only after convergence.** Dormant epic authority and registry-v2 capabilities land with their contracts first; `/cep` calls them only in the final vertical phase after payloads, approvals, docs, and catalogs agree.
- **Use no reviewer tools for CEP.** The frozen structured RFC contains the complete review surface, so generated CEP concerns need no workspace read/search authority.
- **Treat every RFC edit alike.** Even clear-defect revisions invalidate confirmation and require operator reconfirmation plus a new full round.
- **Reuse `b0c0d3` REQ-15.** Epic identity, sibling child plans, membership markers, dependency markers, and `/ci` child selection remain unchanged.
- **Extend `57cc2c` and `6a629b`.** Their complete-outcome and vertical-delivery rules move earlier into decomposition review; they are not superseded.
- **Reuse `34088e` and `8a0644` ownership.** The fleet cap remains owner-local, and `/cep` consumes the scheduler plus `c21cdc` task records without copying admission or persistence semantics.
- **Preserve `a5ad22`'s execution boundary.** Coherency review judges decomposition only; it does not execute children or introduce parallel epic orchestration.
