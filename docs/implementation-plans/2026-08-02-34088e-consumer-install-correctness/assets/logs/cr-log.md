## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] Directly installing dependencies before dependents let receipt-presence checks pass even if the production installer stopped resolving transitive dependencies.
- [1.1] [src:code-review] [sev:Med] Inventory keyed receipts only by embedded plugin name, so misnamed or duplicate receipt files could pass despite filename-based production lookup.
- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=1 outcome=findings summary=med=2 low=0 run=step-1-1-review
- [1.1] [src:code-review] [sev:Med] Case-insensitive installed-path dictionaries allowed case-only destination drift to pass on case-sensitive filesystems.
- [1.1] [src:code-review] [sev:Med] Registry and receipt lookup construction overwrote duplicate mappings instead of rejecting non-exact inventories.
- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=2 outcome=findings summary=med=2 low=0 run=step-1-1-rereview
- [1.1] [src:code-review] [sev:Med] Case-insensitive top-level exclusions treated .GITHUB as the managed .github root on case-sensitive filesystems, hiding an outside write.
- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=3 outcome=findings summary=med=1 low=0 run=step-1-1-final-review
- [1.1] [src:note] [sev:Low] review-cycle-decision stage=step-1.1 after=3 action=continue
- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=4 outcome=clean summary=critical=0 high=0 med=0 low=0 run=step-1-1-final-review-continued
- [1.2] [src:code-review] [sev:Med] Join-Path exemption ignored its base path, allowing RepoRoot-based undeclared scaffold paths to bypass validation.
- [1.2] [src:code-review] [sev:Med] Regex-only dynamic detection missed named Join-Path parameters and interpolated child arguments.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=1 outcome=findings summary=med=2 low=0 run=step-1-2-review
- [1.2] [src:code-review] [sev:Med] RepoRoot-based Join-Path source-tree fallbacks remained invisible to the scanner.
- [1.2] [src:code-review] [sev:Med] Inline CommandParameterAst arguments such as -Path:value bypassed dynamic Join-Path detection.
- [1.2] [src:code-review] [sev:Med] Renaming the undeclared-root baseline test without an enumerated removal broke suite coverage inventory.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=2 outcome=findings summary=med=3 low=0 run=step-1-2-rereview
- [1.2] [src:code-review] [sev:Med] Markdown inline named Join-Path syntax such as -Path:value bypasses dynamic-reference detection.
- [1.2] [src:code-review] [sev:Med] Nested RepoRoot joins inherit an outer PSScriptRoot sidecar command extent and can bypass scaffold validation.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=3 outcome=findings summary=med=2 low=0 run=step-1-2-final-review
- [1.2] [src:note] [sev:Low] review-cycle-decision stage=step-1.2 after=3 action=continue
- [1.2] [src:code-review] [sev:Med] Repo-root Join-Path detection rejected plugins paths but missed scripts/skalary source fallbacks.
- [1.2] [src:code-review] [sev:Med] Markdown colon-bound named Join-Path arguments bypassed dynamic-reference detection.
- [1.2] [src:code-review] [sev:Med] Outer PSScriptRoot sidecar command extents exempted nested RepoRoot scaffold reads.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=4 outcome=findings summary=med=3 low=0 run=step-1-2-review-continued
- [1.2] [src:note] [sev:Low] review-cycle-decision stage=step-1.2 after=4 action=continue
- [1.2] [src:code-review] [sev:Med] Literal Join-Path references were not reconstructed, allowing undeclared static runtime assets to bypass closure validation.
- [1.2] [src:code-review] [sev:Med] PSScriptRoot and AssetRoot sidecar exemptions did not prove the referenced sidecar was manifest-declared or bundled.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=5 outcome=findings summary=med=2 low=0 run=step-1-2-final-authorized-review
- [1.2] [src:note] [sev:Low] review-cycle-decision stage=step-1.2 after=5 action=wrap

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:Med] Smoke probes use unanchored case-insensitive output matching, allowing unexpected output or larger counts to pass.
- [2.1] [src:note] [sev:Low] review-cycle stage=step-2.1 cycle=1 outcome=findings summary=1-Med run-step-2-1-review
- [2.1] [src:note] [sev:Low] review-cycle stage=step-2.1 cycle=2 outcome=clean summary=0-findings run-step-2-1-rereview
- [2.2] [src:code-review] [sev:High] The design-notes init owner is replaced by test-only template-copy logic instead of an installed executable owner.
- [2.2] [src:code-review] [sev:High] The confinement snapshot excludes directories and installed-tree mutations and uses broader hard-coded paths than owner declarations.
- [2.2] [src:code-review] [sev:High] Architecture harvest hostile probes fail prerequisites instead of challenging unconfined StagingRoot write paths.
- [2.2] [src:code-review] [sev:Med] Lifecycle reruns change invocation modes or skip repeat execution, bypassing faithful idempotence and full modified-target checks.
- [2.2] [src:note] [sev:Low] review-cycle stage=step-2.2 cycle=1 outcome=findings summary=3-High-1-Med run-step-2-2-review
- [2.2] [src:code-review] [sev:High] Architecture staging confinement uses unconditional case-insensitive prefix comparison, permitting case-variant sibling escapes on case-sensitive systems.
- [2.2] [src:code-review] [sev:High] Architecture staging validation omits subsequently used adr, schemas, and notes child paths, allowing child symlink escapes.
- [2.2] [src:code-review] [sev:High] Initialize-DesignNotes writes through linked destination ancestors without validating each path segment.
- [2.2] [src:code-review] [sev:Med] Several owners skip modified-target retries and repeat exit outcomes are not checked, allowing failure-shaped idempotence passes.
- [2.2] [src:note] [sev:Low] review-cycle stage=step-2.2 cycle=2 outcome=findings summary=3-High-1-Med run-step-2-2-rereview
- [2.2] [src:code-review] [sev:Med] Design-notes initialization exits when only the index exists, so interruption can leave the second scaffold permanently missing.
- [2.2] [src:code-review] [sev:Med] Lifecycle validation checks created entries but does not require every expanded owner declaration to materialize.
- [2.2] [src:code-review] [sev:Med] Confinement accepts baseline mutations declared by other scaffold owners instead of restricting changes to the active owner.
- [2.2] [src:note] [sev:Low] review-cycle stage=step-2.2 cycle=3 outcome=findings summary=med=3 run=step-2-2-final-review
