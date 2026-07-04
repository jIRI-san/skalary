# Phase 3: Payments hardening

<!-- execution-mode: manual -->
<!-- scope: step -->

## Goal
Harden the payments module: idempotency, retries, reconciliation.

## Steps

- [x] 3.1 Add an `idempotency_key` column to the `payments` table with a unique index. `S`
- [x] 3.2 Thread the idempotency key through `PaymentsService.Charge` and reject duplicate keys. `M`
- [x] 3.3 Add structured logging around the charge path (attempt, success, decline). `S`
- [ ] 3.4 Implement a bounded exponential-backoff retry wrapper for transient gateway `5xx`. `M`
- [ ] 3.5 Add a nightly reconciliation job that diffs gateway settlements against local ledger rows. [after: 3.4] `L`
- [ ] 3.6 Write the runbook entry describing manual reconciliation fallback. `S`
