# Decisions

<!-- Key decisions made during planning — one bullet per decision. Historical detailed decision files are retained as review history; this file records the executable direction. -->

- **Simplicity decision: keep two small phases in this plan.** Consumer-to-upstream learning transport and generic-versus-local review standards remain distinct outcomes with separate steps; no new child plan is created.
- **Transport is one bounded typed export.** It derives from `1936cb` records, carries claims as untrusted data, and is re-judged upstream. It is not a second SI store, history index, or authority record.
- **The upstream checkout owns execution rules.** The handoff uses a clean checkout and normal upstream `/si` or `/cip`; it does not build a cache-generation service, isolated-container platform, credential broker, publication protocol, or merge authority.
- **Standards extend `79cfe1`.** Generic standards share the existing concern source/generator model. Optional local standards live in repo-owned `docs/review-standards.md`, are never installed or overwritten, and enter review through one bounded resolver.
- **Review-run v1 remains authoritative.** Standards become dispatch input; this plan does not add review-run v2, policy/version maps, a second publication lifecycle, or new architecture contracts.
- **Use existing delivery and evidence infrastructure.** Plugin sync/version/registry/marketplace/dogfood writers and current tests remain the distribution and validation path. Rejected: dependency receipts, a global evidence-id registry, paged histories, migration provenance, and exhaustive limit/failure matrices.
- **No dependency on `34088e`.** The transport can be tested with existing installed-consumer infrastructure; foreign-install correctness remains independently schedulable.
