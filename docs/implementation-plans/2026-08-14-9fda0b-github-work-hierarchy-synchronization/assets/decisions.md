# Decisions

- **Deliver GitHub-only v1.** GitHub issues/sub-issues and Projects v2 are the only live provider in this plan.
- **Project locally first.** A pure deterministic projection owns desired hierarchy and managed content before transport is involved.
- **Dry run before apply.** Reads and action rendering are mutation-free; the operator confirms the exact current action set.
- **Use one small `gh` adapter.** Transport and GitHub field mapping stay behind a narrow provider interface seam.
- **Keep one simple mapping.** Canonical local epic/plan IDs map to remote IDs without an append store, journal protocol, or capability publication.
- **Manage explicit regions.** Marker-managed body sections preserve human-authored content outside tool ownership.
- **Refuse conflicts.** Ambiguous adoption, stale state, mapping disagreement, and managed-region edits stop instead of being merged speculatively.
- **Require convergence.** An immediate second run after success is a no-op.
- **Keep real smoke optional.** Focused mocked tests are deterministic evidence; an operator may run a bounded real smoke with their existing `gh` authentication.
- **Defer Azure DevOps.** Preserve the interface seam in code/docs but add no Azure DevOps implementation until a second provider is requested.
- **Reject prior expansion.** No append-store/state protocol, write capability descriptor, activation script, uncertain-outcome state machine, disposable organization provisioning, protected hosted workflow, elaborate credential infrastructure, or new architecture contract is included.
- **Keep one behavioral dependency.** `57cc2c` supplies confirmed intent and plan assets projected into remote work items; epic coherency review is not required to implement synchronization.

## Simplification decision

The accepted 2026-08-22 cut proves useful synchronization through deterministic projection, operator-controlled GitHub writes, and idempotent convergence. Provider and live-smoke infrastructure remain deferred.
