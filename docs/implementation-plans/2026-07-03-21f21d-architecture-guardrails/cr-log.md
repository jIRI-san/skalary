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
- [2.3] [src:code-review] [sev:Med] New-ArchSeed.ps1: missing/null boundaries bypassed the <1 guard (@(null).Count==1) and scaffolded before failing. Fixed: explicit null-reject before counting.
- [2.3] [src:code-review] [sev:Med] New-ArchSeed.ps1: no uniqueness guard on boundary ids -> case-insensitive collision silently dropped a boundary via no-overwrite. Fixed: pre-loop case-insensitive duplicate-id reject.
- [2.3] [src:code-review] [sev:Low] New-ArchSeed.ps1: id could shadow scaffolded artifact basenames / Windows reserved device names. Fixed: reserved-basename reject list. Also resolve -TargetRoot to absolute (CWD vs PWD divergence). Skipped Test-ArchContract -PassThru mode (no functional defect on pwsh 7, verified).

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:High] Import-ArchHarvest.ps1: empty/no-boundary repo crashed under StrictMode ($ordered.Count on $null from empty pipeline), so HARVEST.md was never written. Fixed: wrap Sort-Object in @() so Count is always valid; added empty-repo eval asserting a reviewed:false manifest is still emitted.
- [3.1] [src:code-review] [sev:High] Import-ArchHarvest.ps1: staged notes retained the note template's globs:(<scope>) path-scoped auto-attach front-matter, so quarantined harvested prose could be glob-matched into agent context before human review (RISK-5 leak). Fixed: neutralize front-matter in staged notes (globs -> quarantined:true + stagedScope), restored at promotion; added eval asserting no active globs in staged notes.
- [3.1] [src:code-review] [sev:Low] Import-ArchHarvest.ps1: untrusted package.json name / paths interpolated raw into HARVEST.md table + note body could corrupt/inject markdown. Fixed: ConvertTo-MarkdownCell escapes pipes/newlines for Name/Source.
- [3.1] [src:code-review] [sev:Low] Import-ArchHarvest.ps1: no Windows reserved device-name guard on derived ids (deviation from New-ArchSeed). Fixed: reserved-basename set; ConvertTo-BoundaryId prefixes CON/PRN/AUX/NUL/COM#/LPT# with 'B-'.
- [3.1] [src:code-review] [sev:Low] SKILL Step 7 claimed 'solution files' but only *.csproj scanned. Fixed: broadened .NET scan to *.csproj/*.fsproj/*.vbproj and corrected SKILL wording to match actual scan surface.
- [3.2] [src:code-review] [sev:Critical] New-ArchHumanDoc.ps1: untrusted contract text could inject the literal GENERATED/sha256 marker comments; next regen IndexOf matched the injected end marker, shifting the region splice and corrupting/duplicating narrative (regen DoS). Fixed: ConvertTo-SafeText HTML-escapes angle brackets so marker sentinels cannot appear in the generated region; added injection + regen-stability eval.
- [3.2] [src:code-review] [sev:High] Get-ArchContractsHash.ps1: Sort-Object -Culture '' is InvariantCulture, not ordinal (spec says ordinal); punctuation collation varies across ICU/OS, diverging the digest between generator and freshness gate. Fixed: List.Sort with (string)::CompareOrdinal in both hash helper and generator component order.
- [3.2] [src:code-review] [sev:Med] New-ArchHumanDoc.ps1: Mermaid node label built from untrusted title left quote/bracket chars intact -> label breakout/diagram injection. Fixed: ConvertTo-MermaidLabel neutralizes those chars on top of SafeText.
- [3.2] [src:code-review] [sev:Med] Enumeration: Windows -Filter star-json also matches .jsonc/.json5/8.3 aliases -> cross-platform digest divergence. Fixed: post-filter Extension -eq .json in both hash helper and generator. Nesting deferred: flat schemas/ layout is what New-ArchSeed writes.
- [3.2] [src:code-review] [sev:Med] New-ArchHumanDoc.ps1: malformed contract JSON was silently dropped from the doc while still hashed -> doc loses a contract but gate reports fresh. Fixed: generator now throws on unparseable contract JSON; added eval.
- [3.2] [src:code-review] [sev:Low] New-ArchHumanDoc.ps1: marker IndexOf used CurrentCulture overload. Fixed: pass (StringComparison)::Ordinal. Also corrected redundant BOM TrimStart comment in hash helper (ReadAllText already strips BOM).
- [3.3] [src:code-review] [sev:Med] Test-ArchDocFreshness.ps1: first-match marker read could false-green if a stray/duplicate arch-contracts-sha256 marker was pasted into the hand-authored narrative before the generated one. Fixed: require EXACTLY ONE marker (fail on 0 or >1) and validate it is a canonical 64-hex digest; added duplicate-marker + malformed-digest handling and a duplicate-marker eval.
- [3.3] [src:code-review] [sev:Low] Test-ArchDocFreshness.ps1: helper resolution searches gateRepoRoot before -RepoRoot; a foreign -RepoRoot doc generated by a different-version Get-ArchContractsHash could surface as spurious drift. Documented the same-helper-version assumption + -HashScriptPath escape hatch in-code (moot in dogfood where roots coincide).
- [3.3] [src:code-review] [sev:Low] Evals: missing-marker eval shared Status/exit with the stale-digest branch and never asserted fail-path stderr. Fixed: pin the branch via message match + null Expected, and assert (Console)::Error diagnostics out-of-process (pwsh -File 2>&1, since Console.Error bypasses PS streams in-process).
- [3.3] [src:code-review] [sev:Low] Marker regex is triplicated across gate/generator/eval (no active bug; digest is the single source of truth, marker shape is not). Accepted with mitigation: gate now shape-validates the captured digest so a divergent marker format degrades to fail, never false-pass. Full centralization deferred (needs a shared module across scripts/skalary + plugin scripts).

## CR Capture
Phase: 4

- [4.1] [src:code-review] [sev:Critical] sourcesHash bound only targets not the contract or binding fields; a stale receipt could look fresh after an adapter or contract change. Fixed by folding contractPath plus canonical binding JSON (adapter, spec, testProject, provider, maturity, contractId, sorted targets) into the digest via ExtraContent synthetic record.
- [4.1] [src:code-review] [sev:Critical] Get-ArchGateOutcome greened any verdict=pass regardless of ran, and New-ArchTestReceipt accepted pass with ran false; latent locked false-green. Fixed: gate takes -Ran and only greens a real pass; New-ArchTestReceipt throws on pass plus ran false; receipt schema adds if verdict==pass then ran==true.
- [4.1] [src:code-review] [sev:High] maturity was forbidden by the config schema but read by the runner, making locked hard-gating unreachable. Fixed by adding a maturity enum to the config schema.
- [4.1] [src:code-review] [sev:High] ToLowerInvariant on the relative path made the digest nondeterministic and collision-prone on case-sensitive filesystems. Fixed by keying and sorting on the case-preserving relative path.
- [4.1] [src:code-review] [sev:High] contractId flowed unvalidated into the receipt file path (path traversal). Fixed with a runtime pattern guard in the runner plus ValidatePattern on New-ArchTestReceipt.
- [4.1] [src:code-review] [sev:Med] Receipt bytes were nondeterministic (double trailing newline via Set-Content, un-normalized JSON line endings). Fixed with a BOM-free WriteAllText plus LF normalization and single trailing LF.
- [4.1] [src:code-review] [sev:Med] parentCommit regex admitted 40-hex only, hard-failing SHA-256 repos. Relaxed to 40-or-64 hex in schema and runner.
- [4.1] [src:code-review] [sev:Med] Wildcard-metachar and empty target resolution could silently drop sources. Fixed: only wildcard-resolve when metachars present; warn when a check declares sources but none resolve.
- [4.1] [src:code-review] [sev:Med] Receipt-location prose said beside evidence.md but the runner writes to docs/architecture-notes/receipts. Reconciled SKILL and header prose to the receipts directory. Design-notes entry deferred to the docs phase.
- [4.1] [src:code-review] [sev:Med] Config schema lacked per-adapter requirements. Added allOf if/then: semantic-eval requires provider; deterministic adapters require testProject or spec.
- [4.1] [src:code-review] [sev:Med] Evals never ran Invoke-ArchTests. Added an end-to-end test (locked plus skip blocks, writes schema-valid receipt, HEAD-independent) plus a binding-invalidation test.
- [4.1] [src:code-review] [sev:Low] Hardened dot-source guard (PSCommandPath equality) broke dot-sourcing; reverted to the proven InvocationName guard and kept New-Item hoisted out of the per-check loop.
