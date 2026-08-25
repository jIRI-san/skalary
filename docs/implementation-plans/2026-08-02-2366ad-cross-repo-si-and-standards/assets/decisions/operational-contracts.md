# Operational Contracts

## Dependency receipt

- Writer: `scripts/skalary/Test-DependencyContracts.ps1`.
- Store: `assets/dependency-receipts/<sha256>.json`; `current.json` points to the latest generation and records supersession.
- Revalidation: phases 2 and 4. Missing, unreadable, changed stage, or changed contract digest invalidates the receipt, records a bounded reason, and returns execution to step 0.1 before mutation.

## Handoff result

Canonical schema: `plugins/self-improvement/schemas/si-handoff-result.schema.json`. Installed destination: `.github/skills/si/schemas/si-handoff-result.schema.json`.

| Exit | Class | Retry | Mutation after result | Cleanup |
|---|---|---|---|---|
| `0` | Complete terminal outcome | No | Existing SI terminal receipt only | Release checkout after durable fingerprint/outcome publication |
| `2` | Invalid schema/version/capability/authority | No until corrected | None | Quarantine incomplete generation |
| `3` | Identity/confinement/trust-anchor refusal | No until corrected | None | Quarantine and preserve diagnostics |
| `4` | Retryable network/cache/isolation handoff | Yes | Existing SI `handoff-required` transition only | Reclaim or quarantine as reason specifies |
| `5` | Bounded scan/capacity incomplete | Human/upstream evidence or prune, then retry | Existing SI incomplete-corroboration transition only | Preserve fingerprints; release disposable checkout |

Runbook: `plugins/self-improvement/skills/si/assets/cross-repo-handoff-runbook.md`, installed byte-identically. It carries per-reason Steps, Verify, and Rollback instructions for retry, manual carry, cache repair/purge, isolation failure, durable plan publication, and supersession.

## Checkout and Git

- Machine-owned root: OS-local Skalary cache resolved by one plugin-owned helper; tests inject a confined temporary root.
- Target cache: 10 GiB and 4 immutable generations.
- Quarantine: 2 GiB or 7 days.
- Deadlines: lock 30 seconds, fetch 60 seconds, clone 120 seconds, reclaim 100 entries or 10 seconds, aggregate handoff 240 seconds.
- Git execution: system/global config, hooks, helpers, filters, fsmonitor, SSH/askpass, submodules, LFS, and untrusted alternates disabled. One trusted-sync publish call may receive credentials while retaining every other sanitization control.
- Session: isolated container with only the disposable checkout mounted; checkout root, Git OID, and loaded upstream instruction indexes are attested before candidate text is read.

## SI projection and corroboration

- Projection max: 64 KiB; quoted excerpt max: 4 KiB.
- Persisted history contains fingerprints and typed provenance only, never excerpts or consumer paths.
- Scan: 64 records/page, 4,096 records, 8 MiB, 10 seconds, 256 memo entries; includes active and archived immutable fingerprints.
- Over-limit/time: typed incomplete corroboration, never silent truncation.
- Distinct consumer hashes are claimed source identities. They establish review eligibility only; upstream corroboration and human `/cip` authority remain required.

## Standards and review-run v2

- Generic/local capacity: 96/32 rules.
- Source max: 128 KiB; combined rule+rationale max: 1,536 bytes.
- Per concern and review type: 24 rules, 48 KiB serialized, 12K estimated tokens, 5-second resolution deadline.
- Frozen generation: 336 KiB; complete 14-task standards-token fan-out: 168K.
- Token estimator version is descriptor-owned and parity-tested.
- V2 keeps the 2 MiB input and existing summary/full view budgets. Standards bytes are one deduplicated `standards-generation.<sha256>.json` manifest role; tasks reference its digest. Findings carry at most four rule ids and 3,584-byte bodies.
- Engine-owned admission records base OID, input/generation digests, applied overrides, limits, reason, exit, retryability, and cleanup state. `Get-ReviewRun` verifies and lists interrupted/admission generations.

## Authority order

1. Architecture contracts.
2. Non-overridable agent mechanics and safety rules generated from the concern template.
3. Frozen resolved standards generation.
4. Ledger entries as SI promotion evidence only; never review-dispatch authority.