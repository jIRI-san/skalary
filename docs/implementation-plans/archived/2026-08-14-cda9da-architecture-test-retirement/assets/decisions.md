# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Retire architecture tests, not architecture knowledge.** The architecture-notes tier, human review, and ADR lifecycle remain; executable test machinery is removed.
- **Remove the full runtime contract coherently.** Plugin, adapters, runner, schemas, config, receipts, tests, distribution entries, and documentation are one retirement surface.
- **Retire `arch:` evidence fail-loud.** Remove it from the accepted marker vocabulary and evaluator; generic unknown-marker handling blocks stale active use.
- **Prefer deletion over replacement.** Rejected: introducing another semantic architecture enforcement framework in this plan.
- **Keep digest-pinned human-owned maturity.** `locked` remains authoritative to planning and review through human promotion/authorship; `lockedContentSha256` binds canonical contract content without any runner, receipt, adapter, or fitness verdict.
- **Enforce locked content, not unverifiable identity.** One canonical helper and always-on integrity sweep validate the digest. Human promotion remains reviewer-enforced policy; rejected: treating forgeable local Git author metadata as proof of approval.
- **Trim only runner-specific contract fields.** Remove `frameworks`, `llm`, and `lockedBodySha256`; retain targets and rules/prose/interfaces, replacing the executable-body hash with the runner-independent content digest.
- **Use permanent preview-first source-bound tombstones.** `registry-retirements.json` is canonical, active and retired names are disjoint, and reconciliation mutates only receipts from the verified same source after a persisted preview. See [decisions/retirement-protocol.md](decisions/retirement-protocol.md).
- **Preserve modified consumer residue.** Automatic cleanup deletes only receipt-matching bytes; modified paths retain ownership under a degraded retired receipt and require explicit removal.
- **Reuse one removal engine.** Explicit uninstall and automatic retirement share confinement, hashing, locking, journal, rollback, and pruning; `-Force` on unrelated install/update never authorizes residue deletion.
- **Block rollback-complete reconciliation failures.** Preview, retired, and residue outcomes do not block unrelated requested work; malformed authority or failed recovery does, with no bypass in this plan.
- **Sequence delivery honestly.** Old installed scripts cannot act on new tombstones; automatic behavior begins only after bootstrap or plugin-manager update installs a reconciliation-capable script, which is covered by a pre-retirement fixture.
- **Keep permanent-history checks bounded and host-owned.** A pure-file comparator accepts explicit baseline/candidate blobs; CI materializes exactly one base-branch or previous-main blob. `Test-Registry` remains history-free.
- **Keep one runtime budget authority.** Retirement tests use in-process matrices, at most four subprocesses, one representative hard kill, and the existing platform suite ceilings; no retirement-specific threshold is added.
- **Pin automatic deletion authority in the tombstone.** A mutable receipt can only narrow the tombstone's immutable source/ref/version destination/hash set, never widen it; unknown legacy payloads become `manual-required`.
- **Bound terminal replay globally.** Each invocation handles at most eight retired plugins and 64 recorded paths through a persisted fair cursor, performs no content hashing, and emits one aggregate record.
- **Preserve history.** Archived plans, transcripts, and historical reports stay unchanged; only executable and active instructional surfaces are reconciled.
- **Run container whole-plan without a human finalization gate.** Deterministic focused/full proof and the normal autonomous review loop close the plan; no contract is promoted during this work.
- **Prior art relationship.** Supersede `21f21d` REQ-8 through REQ-11, REQ-14, and REQ-17; reuse its REQ-15 two-index architecture-notes decision; extend `768d7b` D11 from one unsatisfiable `arch:` marker to full runtime retirement.
- **Own the retirement protocol; make `34088e` consume it.** This plan owns the narrow generic mechanism and focused fault matrix; consumer-install correctness depends on it and owns the broader installed-entry-point matrix.
- **Automatic cleanup is operator-required despite added machinery.** Rejected: report-only/manual removal, because the desired end state requires existing consumers to converge; preview-first activation and shared primitives constrain the added risk.
