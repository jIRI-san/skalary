# Decisions

<!-- Key decisions made during planning — one bullet per decision. -->

- **Simplicity decision: test foreign installation only.** The plan owns a manifest-derived foreign fixture, runtime-reference closure, representative installed smokes, scaffold lifecycle, and current distribution drift.
- **Use the production installer and existing test harness.** The fixture never reimplements installation, copies source wildcards, or introduces a per-plugin descriptor/run schema unless a demonstrated harness limitation requires one.
- **Derive attendance from active manifests.** Every active plugin gets one representative installed smoke; additions and retirements change the expected set automatically.
- **Keep installer confinement unchanged.** Installation writes only under `.github/`; declared runtime owners create repo-level scaffolds on first use and preserve modified files.
- **Keep deterministic tests offline.** Smokes use existing process controls and exact prerequisite outcomes without network, provider credentials, or hosted proof receipts.
- **Use existing distribution writers.** Plugin sync, version, dogfood, marketplace, registry, structural evals, and repository validation remain authoritative.
- **Rejected as unrelated or overengineered.** Workflow-limit ownership/parity, the `8a0644` fleet handoff, architecture-retirement transition testing, custom probe protocol/schema, exhaustive process matrix, and a second CI attestation lifecycle are outside this plan. Therefore `34088e` has no dependencies.
