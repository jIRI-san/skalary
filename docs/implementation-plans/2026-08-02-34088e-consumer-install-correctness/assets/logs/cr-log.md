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
