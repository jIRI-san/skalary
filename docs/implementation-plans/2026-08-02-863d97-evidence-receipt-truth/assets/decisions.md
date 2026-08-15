# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Separate execution status, gate findings, and disposition.** Status records what ran, findings record why evidence cannot be trusted, and post-retirement disposition says satisfied, blocked, or waived. See [decisions/evidence-truth-contract.md](decisions/evidence-truth-contract.md).
- **Extend the ordinary suite host for focused evidence.** `Run-UnitTests.ps1` owns full and focused discovery/fault/environment semantics; exact no-space leading tokens bind all cases from tracked `.github/evidence-test-scope.json`, and effective timeout is capped by remaining platform budget.
- **Keep waiver approval human-only and root-owned.** Unattended bundles can read policy but never approve it; root finalization tooling records/revokes the aggregate digest and capture audit. Absent policy is a valid empty set requiring no approval.
- **Use one shared all-tracked-minus-closed-exclusions digest.** A canonical module owns framing, hashing, limits, and class subdigests; v2 publication uses UUID blocked-start/terminal replacement, and `Test-Plan -Stage PlanCrosscheck` becomes authoritative only after all callers migrate.
- **Keep a narrow legacy adapter.** Boolean `Success` maps only when `Status` is absent; contradictory dual input is malformed rather than guessed.
- **Apply the result contract to every marker type.** File and review verifiers retain execution ownership, while all producer outputs normalize through the same state/disposition vocabulary.
- **Execute after architecture-test retirement.** `863d97` depends on `cda9da`; it does not recreate `arch:` evidence, architecture-tests bundles, or `Get-ArchGateOutcome` after retirement.
- **Preserve the evidence opt-in boundary.** Strict plans rebuild old receipts before finalization; non-opted legacy plans remain warn-only. Typed policy replaces prose deferrals and special test-family skip exceptions as evidence waiver authority.
- **Use CI as the installed execution owner.** Continue-implementation bundles focused `Run-UnitTests` and installs the tracked scope; autopilot depends on and invokes it. Parser/schema copies in CIP, CEP, architecture-tests, and dogfood remain generated from canonical sources.
- **Keep ordinary suite hosting with fast seams.** Installed and timeout matrices use injected sub-second seams; no new integration gate is added. Final authority still requires current same-tree Linux and Windows CI rows.
- **Run phase subsets and one complete final crosscheck.** Phase evidence is bounded to that phase's referenced markers; PlanCrosscheck alone reruns the complete inventory.
- **Authorize ordinary-suite skips from active strict plans only.** The suite loads active non-archived marker/policy data once; an exact owned waiver may apply, while archived or unowned skipped IDs fail closed.
- **Verify CI provenance through GitHub API.** A root finalization script authenticates with `gh api` and binds workflow, run, job/platform, conclusion, head SHA, and artifacts; tracked row claims alone are insufficient.
- **Bound conservative hashing at 20,000 files and 30 seconds.** These join the existing byte limits and are enforced before the digest can become a suite-budget escape.
- **Keep review attendance separate.** This plan owns evidence-marker truth; `c21cdc` and `ca8ba8` own review-run and corroboration truth.
- **Document at the design-note tier.** No existing architecture contract is changed and no new provisional contract is added.
