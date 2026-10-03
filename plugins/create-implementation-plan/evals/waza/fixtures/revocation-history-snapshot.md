# Bounded plan/epic history discovery snapshot

## Candidate A — relevant active plan

- Kind: plan
- ID: `token-migration`
- Path: `docs/implementation-plans/standalone-token-migration/plan.md`
- Archive status: active
- Matched section: Confirmed requirements, REQ-4
- Snippet: "Remove token revocation from every API version before migrating existing clients."
- Dependency: active plan `token-migration`, step 2.3 depends on this requirement.
- Current state: client migration is not complete.

## Candidate B — superficially similar archived plan

- Kind: plan
- ID: `billing-notice-refresh`
- Path: `docs/implementation-plans/archive/billing-notice-refresh/plan.md`
- Archive status: archived
- Matched section: Historical note
- Snippet: "Remove revocation language from the billing email template; this plan does not change API behavior."

## Discovery limit

- An index entry points to `docs/legacy-plans/unindexed/`, but the bounded reader could not inspect that location.
- Only the candidates above were returned. This snapshot is not proof that all historical context was found.
