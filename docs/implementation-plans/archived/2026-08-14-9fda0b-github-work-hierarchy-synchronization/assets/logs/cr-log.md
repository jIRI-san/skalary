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
- [2.1] [src:note] [sev:Low] review-cycle-decision stage=step-2.1 after=3 action=wrap
- [2.2] [src:code-review] [sev:High] Updates can overwrite title or body edits made after the initial refresh because expected remote hashes were not consumed immediately before PATCH.
- [2.2] [src:code-review] [sev:High] A successful create can outlive mapping persistence after a crash, ambiguous provider failure, or concurrent apply and then be duplicated by the next dry run.
- [2.2] [src:note] [sev:Low] review-cycle stage=step-2.2 cycle=1 outcome=findings summary=2-high run-apply-review-1
- [2.2] [src:code-review] [sev:High] Update revalidation still has a time-of-check/time-of-use window because the provider PATCH is not conditionally bound to the preceding GET snapshot.
- [2.2] [src:code-review] [sev:High] Search-based orphan recovery can miss a just-created issue during GitHub search indexing delay and permit a duplicate create.
- [2.2] [src:code-review] [sev:Med] A successful update followed by mapping-save failure leaves stale baseline hashes that later dry runs treat as a no-op without repairing.
- [2.2] [src:note] [sev:Low] review-cycle stage=step-2.2 cycle=2 outcome=findings summary=2-high-1-med run-apply-review-2
- [2.2] [src:note] [sev:Low] review-cycle stage=step-2.2 cycle=3 outcome=clean summary=clean run-apply-review-3

## CR Capture
Phase: 3

- [3.1] [src:note] [sev:Low] review-cycle stage=step-3.1 cycle=1 outcome=clean summary=clean run-step-3-1-review
- [3.1] [src:code-review] [sev:Low] Directive-shaped body text used an escaped canary that could not detect execution; use a literal side-effect canary and assert no artifact exists.
- [3.1] [src:code-review] [sev:Low] The ambiguous-adoption dry-run write count was vacuous; pass the refusal-bearing run through apply and prove the provider write boundary stays untouched.
- [3.1] [src:code-review] [sev:Low] The smoke runbook suggested the Git common directory for disposable mapping state; prefer a gitignored or out-of-tree operator-owned path.
- [3.1] [src:note] [sev:Low] review-cycle stage=step-3.1 cycle=2 outcome=findings summary=3-low run-step-3-1-duck
- [3.1] [src:note] [sev:Low] review-cycle stage=step-3.1 cycle=3 outcome=clean summary=clean run-step-3-1-final
- [3.2] [src:code-review] [sev:High] The installed skill imported only GitHubWorkHierarchy, so projection, mapping, dry-run, and apply commands were unavailable; import WorkHierarchy explicitly and assert the public workflow surface.
- [3.2] [src:note] [sev:Low] review-cycle stage=step-3.2 cycle=1 outcome=findings summary=1-high run-step-3-2-review
- [3.2] [src:note] [sev:Low] review-cycle stage=step-3.2 cycle=2 outcome=clean summary=clean run-step-3-2-rereview
- [3.2] [src:note] [sev:Low] review-cycle stage=step-3.2 cycle=3 outcome=clean summary=clean run-step-3-2-duck
- [3.2] [src:code-review] [sev:Med] An existing directory at the mapping path was treated as a missing file, allowing remote writes before persistence failed; reject non-leaf paths before mutation.
- [-] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=1 outcome=findings summary=1-med run-plan-final-review
- [3.2] [src:code-review] [sev:Med] A one-time pre-mutation path check left a TOCTOU window; hold the mapping sidecar lock across refresh, mutations, and checkpoints and revalidate the digest before every provider write.
- [-] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=2 outcome=findings summary=1-med run-plan-final-rereview
- [3.2] [src:code-review] [sev:Med] Update validation still preceded the remote precondition read; revalidate the mapping again after that read and immediately before PATCH.
- [-] [src:note] [sev:Low] review-cycle stage=plan-finalization cycle=3 outcome=findings summary=1-med run-plan-final-third
- [-] [src:note] [sev:Low] review-cycle-decision stage=plan-finalization after=3 action=wrap
