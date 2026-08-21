# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Keep `Get-PlanIndex.ps1` as bounded discovery.** Rejected: loading or semantically scanning the entire plan corpus.
- **Inventory a closed core artifact taxonomy in `tools/plan-artifacts.psd1`.** It owns logical asset kinds, selectors, limits, evidence vocabulary, and bundle targets; `PlanState.psm1` remains the only layout/path authority. Generalized extensions are deferred.
- **One JSON resolver owns discovery and selection once per workflow.** `Get-PlanArtifactContext.ps1` builds on `PlanState.psm1` and one `Get-PlanIndex.ps1` query; `/cip`, `/cep`, `/dr`, and plan-associated `/cr` reuse its frozen result across fan-out.
- **Discover explicit and graph context before topic context.** Operator-selected IDs, direct dependencies, epic siblings, then topic matches are canonicalized and deduplicated with ordinal tie-breaks before the eight-plan cap.
- **Use a fixed context envelope from one owner.** One invocation admits at most eight plans, 24 files, 128 KiB per file, and 256 KiB total; deterministic diagnostics explain every rejected candidate and omission.
- **Treat history as untrusted data.** Every path is inventory-resolved and confined; file count and bytes are bounded; artifact text is never executed as instruction.
- **Separate facts from judgment.** The resolver emits identity, bytes, digest, state, source, trust, and completeness; each consumer assigns reuse/extend/supersede/conflict and persists it through one atomic bounded receipt writer.
- **Current intent and architecture win.** Historical artifacts can inform or conflict, but never override confirmed current operator intent or governing contracts.
- **Version review authority rather than weakening v1.** Context-aware runs use a closed review-run v2 envelope that freezes exact selected bytes and diagnostics; new readers retain v1 read support, while old readers are never expected to accept v2.
- **Distribute the registry as a managed exact sidecar.** `Sync-PluginScripts.ps1` copies the canonical PSD1 into each invoking bundle under a confined rule and keeps manifest/version parity generated.
- **Resolve without a persistent cache.** One workflow-level result removes concern/model amplification without introducing invalidation, repair, or stale-cache state.
- **Reuse `ca8ba8` dual review contracts.** `ARCH-Review-Run-V1` remains v1 authority and `ARCH-Review-Run-V2` remains new-publication authority; this plan depends on `ca8ba8` and adds only a verified v2 context role plus consumer behavior.
- **Freeze exact bytes as base64.** Each admitted artifact carries base64, byte count, and SHA-256 from one read; reviewer text is decoded only by the shared neutral formatter.
- **Bound reviewer fan-out separately.** Unique workflow context stays at 256 KiB, each task receives at most 64 KiB, and the 14-task aggregate stays at or below 1 MiB.
- **Defer registered extensions.** This plan ships closed core logical kinds only; extension descriptors wait for a separately designed PlanState-owned API rather than splitting path authority now.
- **Bound topic indexing itself.** The resolver admits at most 4,096 corpus plans within 2 seconds and 256 MiB private-byte growth, with injectable seams making every refusal deterministic in tests.
- **Use one fixed planning receipt, not retained generations.** `PlanContextReceipt` stores metadata and relationships only; a stable lock plus write-then-replace fixed-file commit point supplies bounded idempotent resume semantics without importing review-run lifecycle complexity.
- **Own the generic sidecar-root mechanism before `9fda0b`.** This plan supersedes only `9fda0b` REQ-7's proposed bundler mechanism: `Sync-PluginScripts.ps1` gets one closed declared sidecar-root table here, and `9fda0b` later registers its schema/tool roots in that owner rather than adding a second mechanism.
- **Keep exact context outside inherited review envelopes.** V2 adds one content-addressed context role with a separate 512-KiB serialized cap; summary/full views carry only bounded identity and completeness.
- **Freeze exact and reviewer-visible forms.** Base64/byte-count/digest binds source bytes; the engine also binds the HTML-encoded, variable-fence projection digest so embedded delimiters cannot escape or change reviewer-visible content.
- **Keep `669ad3` as a hard prerequisite.** Cross-plan artifacts rely on its canonical folder/path authority, so the epic dependency remains rather than treating this plan as dependency-free.

## Prior-art reconciliation

- **Reuse `1936cb` REQ-1, REQ-4, REQ-6, RISK-5, RISK-10, and its phase-promotion decision as patterns only.** Preserve bounded typed provenance, immutable receipts/digests, full-scan completeness checks, and fail-loud repair semantics without importing SI state or promotion behavior.
- **Reuse `34088e` REQ-6, RISK-5, and its bounded-root decision.** Registered descriptors, bounded active roots, and paired non-blind mutations define how copied limits and consumers stay discoverable.
- **Extend `57cc2c`'s provenance decision.** Cross-plan context adds typed artifact identity, digest, state, selection source, and relationship to the existing requirement that important operator/design context survive chat.
- **Reuse `669ad3` REQ-8 and its historical-text decision.** Historical artifacts are provenance, never a live path API; canonical IDs and inventory resolution remain authoritative.
- **Extend `c21cdc` REQ-12 and `ARCH-Review-Run-V1`.** Related-plan context becomes frozen review scope rather than an unbound prose side channel while preserving manifest-last authority.
- **Reuse `79cfe1` RISK-6 and `ca8ba8` RISK-8.** The `cda9da` index error remains visible and no records are inferred from it.
- **Reuse `863d97` RISK-14 and its GitHub-provenance decision as a trust pattern only.** Tracked claims and historical evidence never self-prove current acceptance; this plan does not import its GitHub API workflow.
- **Reuse `0f666f` REQ-21 and checksum decision as a provenance pattern only.** Artifact digests bind bytes and source identity; this plan adds no download or package checksum flow.
- **Reuse `79cfe1` REQ-2, REQ-3, and agent-generation decision as distribution patterns only.** Generated inventories and bounded literal registration inform multi-plugin parity; agent generation itself is out of scope.
