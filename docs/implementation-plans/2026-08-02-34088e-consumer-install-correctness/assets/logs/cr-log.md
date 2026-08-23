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
