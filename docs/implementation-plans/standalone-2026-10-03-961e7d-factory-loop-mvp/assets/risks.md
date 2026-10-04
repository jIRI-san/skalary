# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Global existing skills assume repository-local installed paths. | High | Medium | Explicit first-use local dependency bootstrap; stop if this requires broad path-framework refactoring. Test plugin assets outside the selected repo. | 1.1 |
| RISK-2 | Canned simulated success hides a broken application. | Medium | High | Acceptance executes immutable demo code; include planted defect, version mismatch and working-tree-change assertions. | 1.2 |
| RISK-3 | Crash after mutation causes duplicate PR/bug/promotion. | High | High | Stable operation keys plus provider lookup before retry; unknown result pauses. Exercise each post-side-effect crash boundary. | 2.1 |
| RISK-4 | Unattended repair bypasses confirmation or weakens criteria. | Medium | High | Parent-confirmed bounded repair admission, read-only criteria baseline and operator scope expansion. Stop before writing a new confirmation marker or altering acceptance. | 2.2 |
| RISK-5 | Pipeline success/stale version or inaccessible telemetry creates false success. | High | High | Require exact artifact mapping, current checks and successful query coverage. Pause identity/access uncertainty. | 3.1 |
| RISK-6 | Alert noise creates unbounded fixes or unsafe prod action. | Medium | High | Stable incidents, attribution triage, two repair PRs, new artifact approval, read-only prod default; no auto rollback/merge. | 3.2 |
| RISK-7 | Evidence leaks data or triggers a deployment cycle. | Medium | High | Sanitize to bounded summaries, refuse secrets/customer payloads, separate worktree and excluded branch; readiness stops if exclusions unresolved. | 4.1 |
| RISK-8 | Agent evals cost money or escape fixture isolation. | Medium | High | Offline deterministic acceptance and small premium cases; require disposable isolation for writes. Stop rather than run write-enabled evals in the live checkout. | 4.2, 4.3 |
