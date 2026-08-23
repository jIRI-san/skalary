# Decisions

- **Keep `Get-PlanIndex` as discovery.** Topic matches, explicit epic/dependency relationships, and operator choices identify candidate plan IDs; the resolver does not rescan or load the corpus wholesale.
- **Accept resolved IDs only.** Plan resolution remains owned by existing `PlanState.psm1`; the new helper resolves artifact content, not fuzzy identities.
- **Use a closed artifact-kind allowlist.** Each kind maps through existing layout and asset-path resolution.
- **Return content plus metadata.** Plan ID, kind, repo-relative path, and relationship travel with every accepted artifact.
- **Treat history as untrusted.** Related-plan content may inform work but never overrides current confirmed intent or architecture contracts.
- **Record provenance in existing places.** Planning writes `references.md`; plan-associated reviews bind metadata in their existing scope.
- **Use one consumer path.** `/cip`, `/cep`, and optional plan-associated `/dr` and `/cr` call the same bounded resolver.
- **Keep review-run v1 unchanged.** Context loading does not create a context role, review version, receipt, lifecycle, or publication format.
- **Reject prior platform expansion.** No sidecar root registry copied across plugins, `PlanContextReceipt`, receipt state machine, v2 context role/review lifecycle, budget algebra, dedicated platform receipt, or new architecture contract is included.
- **Reject infrastructure-only dependencies.** This plan has no dependency on folder naming or review corroboration; existing identity and layout resolution already provide its required behavior.

## Simplification decision

The accepted 2026-08-22 cut is one bounded resolver beside `Get-PlanIndex`, shared by all consumers and backed by existing layout helpers. Additional protocols are deferred until a demonstrated resolver failure requires them.
