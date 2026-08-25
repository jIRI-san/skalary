# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Recovered operator decisions

- Copilot session `8706d364-f92e-4056-bb1b-40a59b015d38`, turns 32–37: use a generic once-approved script, JSON `-FindingPath` rather than generated PowerShell, reduce the measured 66 KB collated report, and preserve independent discovery by deduplicating only at render time.
- [Review system enforcement gaps](../../../design-notes/explorations/review-system-enforcement-gaps.design.md): Cluster A attendance/degradation gaps and Cluster D data-as-code plus unbounded report findings.

## Prior-art reconciliation

- Plan `b0c0d3` REQ-18 and decision **Collation is a script, not a prompt** are **extended**: one canonical deterministic formatter still owns merge, elevation, order, and layout for both review types.
- Plan `b0c0d3` REQ-18's typed-object-only invocation and its no-file-I/O purity constraint are **superseded narrowly** by D1. They force reviewer data into generated PowerShell source and prevent a stable `pwsh -File` command. The report behavior, shared ownership, and deterministic-output intent remain.
- Plan `b0c0d3` RISK-1 and its runtime-model decision are **reused**: a served model cannot attest its identity. This plan records only the declared dispatch model and makes no stronger claim.
- Plan `b0c0d3` RISK-4 and its 28-invocation budget decision are **reused but not re-owned**: dispatch selection/budget remain outside this plan; task records truthfully report what that dispatcher planned and completed.
- Plan `768d7b` leaves Cluster A review attendance open and is **reused as status evidence**, not superseded.
- Sibling `ca8ba8` has no settled requirements yet. Its [boundary note](../../2026-08-08-ca8ba8-review-corroboration-truth/assets/references.md) is **resolved** by making it depend on `c21cdc` and extend the v1 artifact rather than co-owning its shape.
- `Get-PlanIndex.ps1 -Filter 'review|report|collat|attendance|finding' -Format Json` returned no index errors on 2026-08-14.

## Current implementation

- [Canonical formatter](../../../../scripts/skalary/Build-ReviewReport.ps1): object input, exact-key merge, exact-roster elevation, ordinal rendering, and caller-owned output writes.
- [CR collation guide](../../../../plugins/code-review/skills/cr/assets/collation-guide.md) and [DR collation guide](../../../../plugins/design-review/skills/dr/assets/collation-guide.md): currently require generated `[pscustomobject]` code and forbid `pwsh -File`.
- [Formatter tests](../../../../tests/skalary/Build-ReviewReport.Tests.ps1) and [bundle/caller tests](../../../../tests/skalary/ReviewReportBundle.Tests.ps1): pin the behavior this plan must migrate without silently losing coverage.
- PowerShell 7.6.4 capability probe (2026-08-14): built-in `Test-Json -SchemaFile` accepted the required draft-2020-12 `prefixItems` probe and rejected its invalid twin; implementation must repeat this against the minimum supported version.
- Plan `8a0644` dispatch-plan-up-front now depends on `c21cdc`: it owns future fleet planning and emits the frozen task contract rather than redefining attendance persistence/rendering.
- [Security ledger](../../../review-ledger/security.md): fail closed on malformed content rather than turning authoring/parse failure into a silent bypass.
- [Observability ledger](../../../review-ledger/observability.md): diagnostics must survive the exact failure path they describe.

No current architecture-note contract applies directly; this plan does not alter installer confinement or the deterministic/LLM eval gate boundary.
