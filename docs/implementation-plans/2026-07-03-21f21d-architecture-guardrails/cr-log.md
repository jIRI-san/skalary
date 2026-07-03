## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Low] Test-Json draft-2020-12 schema conformance may wrong-fail on pwsh 7.0-7.3; accepted no-action (repo convention #requires 7.0; CI/dev runtime 7.4+, verified pass on 7.6.3).
- [1.2] [src:code-review] [sev:Med] created-action reported outside ShouldProcess in Copy-ArchScaffold.ps1; FIXED (action set inside gate, whatif path distinct).
- [1.2] [src:code-review] [sev:Med] locked contract did not require lockedBodySha256; FIXED (schema if/then requires hash when maturity=locked; test added).
- [1.2] [src:code-review] [sev:Med] asset-root auto-detect picked any existing dir and was untested; FIXED (require schemas/ subtree in candidate; added no-AssetRoot resolution test).
- [1.2] [src:code-review] [sev:Low] flat (non-recursive) scaffold copy could silently skip nested subtrees; documented flat-dir assumption in-code (revisit with -Recurse when templates add subtrees).
- [1.3] [src:code-review] [sev:Med] index template had globs:** frontmatter unlike sibling .design-notes.md (latent glob-scanner auto-load hazard, RISK-4); FIXED (removed frontmatter to match convention).
- [1.3] [src:code-review] [sev:Low] dest dir created via New-Item -Path (wildcard-unsafe); FIXED with (IO.Directory)::CreateDirectory (New-Item lacks -LiteralPath).
- [1.4] [src:code-review] [sev:Low] registry.json/README/dogfood mirror all generated (Build-Registry + Sync-Dogfood); cr verified byte-level match, REQ-1 satisfied. No findings.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Test-ArchContract.ps1: hard exit dropped buffered pipeline output on invalid contracts (CLI gate saw empty stdout). Fixed: write diagnostics synchronously to stderr before exit 1; keep object on pipeline for in-process callers.
- [2.1] [src:code-review] [sev:Med] SKILL Step 6.2 referenced assets/interview-guide.md which ships later (step 2.3). Softened to conditional reference.
- [2.1] [src:code-review] [sev:Med] Evals only exercised in-process (& script), missing CLI surface. Added out-of-process pwsh -File eval asserting exit 1 + stderr errors.
- [2.1] [src:code-review] [sev:Low] Schema walk-up unbounded + un-normalized SchemaPath. Fixed: stop at repo boundary (.git / docs/architecture-notes) and Resolve-Path the walk-up hit.
- [2.2] [src:code-review] [sev:Low] cr(prompts): no findings — frontmatter/links/op-mapping/guardrails clean. Applied optional hardening: eval asserts each wrapper presets its operation.
- [2.2] [src:code-review] [sev:Critical] dr(REQ-4): 12 findings (4 Critical). APPLIED now (SKILL prose): script-path HALT-if-missing + installed/source layout clarified; removed circular /uan human-doc regen ref; defined provisional maturity; /cip->/can in seed Step 6.4. DEFERRED to later phases (machine-enforcement): lock gate not enforced by validator (Phase 6 REQ-18), locked-mutation/demotion holes (Phase 6), harvest quarantine before auto-load (Phase 3 REQ-6), autonomous-context detection (Phase 6), lockedBodySha256 canonical compute/verify script (Phase 6), Review runner+taxonomy integration (Phase 5/6), promotion-proposal artifact+audit (Phase 6), seed-interview determinism (Phase 2 step 2.3).
