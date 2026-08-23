## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] Projection accepted duplicate canonical child IDs or an epic/child ID collision, making remote identity ambiguous; fail closed before emission.
- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=1 outcome=findings summary=1-high run-step-1-1-review
- [1.1] [src:code-review] [sev:Low] Archived epic members are projected intentionally so completed work remains in the hierarchy; document the inclusion contract.
- [1.1] [src:code-review] [sev:Med] The real gh runner merged stderr into successful JSON stdout, so benign warnings could break parsing; capture streams separately.
- [1.1] [src:code-review] [sev:Low] Child Sort-Object ordering did not guarantee the documented ordinal canonical-ID contract; use StringComparer.Ordinal.
- [1.1] [src:code-review] [sev:Low] Malformed GitHub issue JSON produced opaque StrictMode property errors; validate the adapter result shape explicitly.
- [1.1] [src:code-review] [sev:Low] Plan step annotations remain in projected phase text intentionally to preserve local execution semantics for readers.
- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=2 outcome=findings summary=1-med-4-low run-step-1-1-duck
- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=3 outcome=clean summary=clean run-step-1-1-final-review
- [1.2] [src:code-review] [sev:Med] Unmapped in-epic dependency targets were refused instead of linked after their create actions.
- [1.2] [src:code-review] [sev:Med] The GitHub issues endpoint can return pull requests, which the adapter accepted as issues.
- [1.2] [src:code-review] [sev:Med] Native gh output limits were checked only after ReadToEndAsync buffered the full response.
- [1.2] [src:code-review] [sev:Med] Mapping refusals were emitted before normal item traversal, violating parent-then-child action ordering.
- [1.2] [src:code-review] [sev:Med] A valid managed marker pair plus an extra malformed marker-prefixed comment was accepted.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=1 outcome=findings summary=5-med run-step-1-2-review
- [1.2] [src:code-review] [sev:Low] A one-page relation read made the greater-than-100 guard unreachable; probe the 101st item and refuse overflow.
- [1.2] [src:code-review] [sev:Low] PRs in relation results remain a fail-closed adapter error rather than being skipped or converted into partial state.
- [1.2] [src:code-review] [sev:Low] Mapping repository comparison was case-sensitive even though GitHub owner/repository identity is case-insensitive.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=2 outcome=findings summary=3-low run-step-1-2-duck
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=3 outcome=clean summary=clean run-step-1-2-final-review

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Mapping numbers are cast before validation and duplicate numbers are not marked ambiguous.
- [2.1] [src:code-review] [sev:Med] GitHub issue 404s throw before core missing-target refusal can be rendered.
- [2.1] [src:code-review] [sev:High] Locking the mapping inode does not prevent Unix pathname replacement races.
- [2.1] [src:code-review] [sev:Med] Truncating before writing can destroy the prior mapping on interruption or write failure.
- [2.1] [src:code-review] [sev:Med] Read and save digest BOM-bearing UTF-8 mapping bytes differently.
- [2.1] [src:note] [sev:Low] review-cycle stage=step-2.1 cycle=1 outcome=findings summary=5-findings-run-review-step-2-1
- [2.1] [src:code-review] [sev:Med] Duplicate identity preflight ignores mapping entries outside the current projection.
- [2.1] [src:code-review] [sev:Med] Dry run accepts invalid or projection-mismatched mapping kinds.
- [2.1] [src:code-review] [sev:Med] Issue 404 classification can conceal inaccessible or missing repositories.
- [2.1] [src:note] [sev:Low] review-cycle stage=step-2.1 cycle=2 outcome=findings summary=3-findings-run-review-step-2-1-fixes
- [2.1] [src:code-review] [sev:Med] Invalid entries bypass collision indexing for their otherwise valid issue number or provider ID.
- [2.1] [src:note] [sev:Low] review-cycle stage=step-2.1 cycle=3 outcome=findings summary=1-finding-run-review-step-2-1-final
