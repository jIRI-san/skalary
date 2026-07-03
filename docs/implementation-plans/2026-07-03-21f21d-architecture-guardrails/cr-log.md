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
