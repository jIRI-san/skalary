How to read this receipt: the phase sections are chronological and each was written when that
phase ran, so a ✗ inside one is that phase's own state at that commit — every one of them names
the later step that executed the marker (`unrun: lands in step 4.3`, `lands in step 9.1`). The
`Plan 768d7b Final Crosscheck` at the end is the only section that describes the tree as it
stands: every required marker re-executed at HEAD, plus the risk register.

Phase 1 Crosscheck:
✓ REQ-1 — file:tools/suite-profile.json#exists — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-1 — test:SuiteProfile.RecordsPerOperationCosts — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-1 — test:SuiteProfile.CoversWholeTestTree — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-2 — file:tools/suite-budget.psd1#exists — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-2 — test:SuiteBudget.CeilingIsPerPlatform — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-2 — test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-2 — test:SuiteBudget.AbsoluteCapIs900 — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-2 — test:SuiteBudget.MeasuresFullNpmTest — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✗ REQ-2 — test:SuiteBudget.OverBudgetRunFails — unrun: lands in step 4.3 — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-3 — test:SuiteCoverage.TestNameInventoryPreserved — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-3 — test:SuiteCoverage.ConfinementCasesRetained — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3
✓ REQ-3 — test:SuiteFixture.CarriesTagsForVersionResolution — passed — 69ad2245b5d29fda812a020c23592a8b67ce33b3

Phase 2 Crosscheck:
✓ REQ-3 — test:SuiteCoverage.TestNameInventoryPreserved — passed — 58294c36ff8e5d6b573b57865b3125acb9a8581b
✓ REQ-3 — test:SuiteCoverage.ConfinementCasesRetained — passed — 58294c36ff8e5d6b573b57865b3125acb9a8581b
✓ REQ-3 — test:SuiteFixture.CarriesTagsForVersionResolution — passed — 58294c36ff8e5d6b573b57865b3125acb9a8581b
✓ REQ-4 — file:tools/suite-profile.json#contains:phase — passed: phase 2 row: 8.775s -> 1.827s on New-RepoClone, saving 6.948s against a declared 4.4s — 58294c36ff8e5d6b573b57865b3125acb9a8581b
✓ REQ-4 — test:SuiteProfile.PhaseTargetsMet — passed: stop condition; targets pinned in tools/suite-budget.psd1 — 58294c36ff8e5d6b573b57865b3125acb9a8581b
✗ REQ-4 — test:SuiteBudget.WithinHardCeiling — unrun: lands in step 4.3 — 58294c36ff8e5d6b573b57865b3125acb9a8581b

Phase 5 Crosscheck:
✓ REQ-5 — file:scripts/skalary/Run-UnitTests.ps1#contains:PesterNotInstalled — passed: re-verified at HEAD: step 4.3 added the budget check to this same script, so the 57175f0 binding no longer covered the file — 456dd67ff5a783e6504bdeed4ee2cf1289e68914
✓ REQ-5 — test:RunUnitTests.MissingPesterExitsNonZero — passed — 456dd67ff5a783e6504bdeed4ee2cf1289e68914
✓ REQ-5 — test:RunUnitTests.ZeroTestsDiscoveredFails — passed: both shapes red: a file declaring no test, and an empty tests tree; each stays separable from a run that tested and failed — 456dd67ff5a783e6504bdeed4ee2cf1289e68914

Phase 7 Crosscheck:
✓ REQ-7 — file:scripts/skalary/Build-Registry.ps1#contains:StringComparer — passed: re-verified at HEAD through Test-Plan.ps1 -EvidenceMarker; Build-Marketplace.ps1 and the Test-Registry.ps1 drift gate carry the same ordinal comparer — 1144dc2fd3b35454abffeb3e17e0aa58be9aa33d
✓ REQ-7 — test:BuildRegistry.CzechCollationFixtureIsStable — passed: re-verified at HEAD: 7d1bbf7 rewrote BuildRegistryCollation.Tests.ps1 host-independently after the 633aab9 binding, so that binding no longer covered the test — 1144dc2fd3b35454abffeb3e17e0aa58be9aa33d
✓ REQ-7 — test:BuildRegistry.FixtureIsRedBeforeFix — passed: re-verified at HEAD; the fixture still collates chata/cukr/hrad differently between cs-CZ and en-US, so the stability assertion is non-vacuous — 1144dc2fd3b35454abffeb3e17e0aa58be9aa33d
✓ REQ-8 — test:Validate.DotPrefixedPayloadEnumerated — passed: re-verified at HEAD — 1144dc2fd3b35454abffeb3e17e0aa58be9aa33d
✓ REQ-8 — test:Validate.GitDirectoryNotEnumerated — passed: re-verified at HEAD; RISK-5 negative case, with reparse points rejected rather than followed — 1144dc2fd3b35454abffeb3e17e0aa58be9aa33d
✓ REQ-8 — test:Validate.FileCountEqualAcrossPlatforms — passed: re-verified at HEAD — 1144dc2fd3b35454abffeb3e17e0aa58be9aa33d

Phase 3 Crosscheck:
✓ REQ-3 — test:SuiteCoverage.TestNameInventoryPreserved — passed — a8e50e784cd38b6bc5f8a0f6906377261e3d6400
✓ REQ-3 — test:SuiteCoverage.ConfinementCasesRetained — passed — a8e50e784cd38b6bc5f8a0f6906377261e3d6400
✓ REQ-3 — test:SuiteFixture.CarriesTagsForVersionResolution — passed: order-independence for the tag is covered by test:SuiteOrdering.RandomisedOrderGivesIdenticalResults (RISK-12) — a8e50e784cd38b6bc5f8a0f6906377261e3d6400
✓ REQ-4 — file:tools/suite-profile.json#contains:phase — passed: phase 3 row: 95.847s -> 78.17s on the run, saving 17.677s against a declared 10.0s — a8e50e784cd38b6bc5f8a0f6906377261e3d6400
✓ REQ-4 — test:SuiteProfile.PhaseTargetsMet — passed: stop condition; phase 3 target pinned in tools/suite-budget.psd1 — a8e50e784cd38b6bc5f8a0f6906377261e3d6400
✗ REQ-4 — test:SuiteBudget.WithinHardCeiling — unrun: lands in step 4.3 — a8e50e784cd38b6bc5f8a0f6906377261e3d6400


Phase 4 Crosscheck:
✓ REQ-2 — file:tools/suite-budget.psd1#exists — passed — 36334d66fa0e60ee82db95326afd65ee181a0f37
✓ REQ-2 — test:SuiteBudget.CeilingIsPerPlatform — passed — 36334d66fa0e60ee82db95326afd65ee181a0f37
✓ REQ-2 — test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification — passed: no raise taken; both ceilings at or below the bound 600s — 36334d66fa0e60ee82db95326afd65ee181a0f37
✓ REQ-2 — test:SuiteBudget.AbsoluteCapIs900 — passed — 36334d66fa0e60ee82db95326afd65ee181a0f37
✓ REQ-2 — test:SuiteBudget.MeasuresFullNpmTest — passed — 36334d66fa0e60ee82db95326afd65ee181a0f37
✓ REQ-2 — test:SuiteBudget.OverBudgetRunFails — passed: runner exits 5 naming measured and budgeted; 6 for an unbudgeted or malformed entry — 36334d66fa0e60ee82db95326afd65ee181a0f37
✓ REQ-4 — test:SuiteBudget.WithinHardCeiling — passed: Linux 108.998s of 330s, Windows 223.142s of 600s, both measured on the CI runners — 36334d66fa0e60ee82db95326afd65ee181a0f37
✓ REQ-4 — file:tools/suite-profile.json#contains:phase — passed — 36334d66fa0e60ee82db95326afd65ee181a0f37

Phase 6 Crosscheck:
✓ REQ-6 — file:scripts/skalary/PlanState.psm1#contains:PlanStageOrder — passed: re-verified at HEAD: PlanStageOrder is the single ordered, closed set and Get-PlanStageOrder is its only publisher — f5d539737d90f75b04251a196b7b67a5d51819b6
✓ REQ-6 — test:ValidatePlan.ScaffoldedPlanReportsSkipped — passed: 3 cases green: the skip carries a distinguishable signal, an all-scaffold tree still reports skipped, and both npm test legs share one floor — f5d539737d90f75b04251a196b7b67a5d51819b6
✓ REQ-6 — test:ValidatePlan.DraftedPlanStillValidated — passed: 2 cases green: a drafted plan is validated and a broken one still fails; a missing anchor resolves to drafted (RISK-7) — f5d539737d90f75b04251a196b7b67a5d51819b6
✓ REQ-6 — test:ValidatePlan.UnknownStageFailsLoud — passed: an unrecognised stage throws rather than resolving to a skip (RISK-6) — f5d539737d90f75b04251a196b7b67a5d51819b6

Phase 8 Crosscheck:
✓ REQ-2 — file:tools/suite-budget.psd1#exists — passed: re-verified at HEAD through Test-Plan.ps1 -EvidenceMarker; the ceilings the workflow timeouts are checked against — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-2 — test:SuiteBudget.CeilingIsPerPlatform — passed — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-2 — test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification — passed: no raise taken in phase 8 — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-2 — test:SuiteBudget.AbsoluteCapIs900 — passed — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-2 — test:SuiteBudget.MeasuresFullNpmTest — passed: CI reproduces the npm test span across separate named steps through the budget clock, so the figure CI enforces is the whole command — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-2 — test:SuiteBudget.OverBudgetRunFails — passed: step 8.1 entry check (D9): npm test exit 0 at 97.812s, re-measured 101.363s at phase end against the 330s Linux ceiling — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-9 — test:Ci.InvokesRunUnitTests — passed: one job, two-OS matrix; Run-UnitTests.ps1 and validate.ps1 in separate named steps, no Invoke-Pester — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-9 — test:Ci.DeclaresLeastPrivilege — passed: top-level permissions is exactly contents: read, no job-level override, persist-credentials false, trigger stays pull_request — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-9 — test:Ci.ActionsAndModulesPinnedWithoutSkipPublisherCheck — passed: actions SHA-pinned, modules pinned to an exact NuGet range, -SkipPublisherCheck and global PSGallery trust both absent, -AuthenticodeCheck restored where the platform supports it — 100ed125b11b8120bed34290aa55a0ee73f5af93
✓ REQ-9 — test:Ci.ArtifactNamePerPlatform — passed: per-OS NUnit path and artifact name, uploaded if: always(), one summary line per leg — 100ed125b11b8120bed34290aa55a0ee73f5af93
✗ REQ-9 — test:Ci.SeededFailureIsRed — unrun: lands in step 9.1 — 100ed125b11b8120bed34290aa55a0ee73f5af93

Phase 9 Crosscheck:
✓ REQ-2 — file:tools/suite-budget.psd1#exists — passed: RISK-9: re-verified at HEAD after phases 7-9 added tests; the ceiling is still the one bound in phase 1 — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.CeilingIsPerPlatform — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification — passed: no raise taken across the whole plan; both ceilings at or below the bound 600s — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.AbsoluteCapIs900 — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.MeasuresFullNpmTest — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.OverBudgetRunFails — passed: final tree: npm test exit 0, 762 tests, 103.629s against the 330s Linux ceiling and 240s target — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.InvokesRunUnitTests — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.DeclaresLeastPrivilege — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.ActionsAndModulesPinnedWithoutSkipPublisherCheck — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.ArtifactNamePerPlatform — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.SeededFailureIsRed — passed: step 9.1: the workflow own unit-test command run against a seeded failing tree exits 1 with the failure named in the NUnit report, and no step can swallow it; 8 mutations each turned this test red — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-10 — file:docs/design-notes/project/ci-gates.design.md#exists — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-10 — test:CiGates.InventoryMatchesWorkflow — passed: step 9.2: 16 rows mapped both ways against the workflow steps and validate.ps1 syntax tree; 3 typed exclusions declared — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec


Plan 768d7b Final Crosscheck:
Requirements: 10/10 satisfied
✓ REQ-1 — file:tools/suite-profile.json#exists — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-1 — test:SuiteProfile.RecordsPerOperationCosts — passed: per-operation counts and aggregate seconds for New-RepoClone, Install-Plugin, Build-Registry, Test-Registry — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-1 — test:SuiteProfile.CoversWholeTestTree — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — file:tools/suite-budget.psd1#exists — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.CeilingIsPerPlatform — passed: Linux 330s/240s, Windows 600s/450s — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification — passed: the D1 hatch was never used: both ceilings only fell — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.AbsoluteCapIs900 — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.MeasuresFullNpmTest — passed: the clock spans npm test rather than the test:unit leg (D2) — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-2 — test:SuiteBudget.OverBudgetRunFails — passed: runner exits 5 naming measured and budgeted, 6 for an unbudgeted or malformed entry — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-3 — test:SuiteCoverage.TestNameInventoryPreserved — passed: the pre-rewrite inventory is a subset of the current tree — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-3 — test:SuiteCoverage.ConfinementCasesRetained — passed: RISK-2 must-keep set intact — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-3 — test:SuiteFixture.CarriesTagsForVersionResolution — passed: RISK-12: the loss the name inventory structurally cannot detect — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-4 — test:SuiteBudget.WithinHardCeiling — passed: Linux 108.998s of 330s, Windows 223.142s of 600s, measured on the CI runners — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-4 — file:tools/suite-profile.json#contains:phase — passed: phase 2 saved 6.948s of a declared 4.4s; phase 3 saved 17.702s of a declared 10.0s — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-5 — file:scripts/skalary/Run-UnitTests.ps1#contains:PesterNotInstalled — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-5 — test:RunUnitTests.MissingPesterExitsNonZero — passed: exit 2, naming the install command, and separable from a run that tested and failed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-5 — test:RunUnitTests.ZeroTestsDiscoveredFails — passed: both shapes red: a file declaring no test, and an empty tests tree — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-6 — file:scripts/skalary/PlanState.psm1#contains:PlanStageOrder — passed: one ordered, closed set with a single publisher — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-6 — test:ValidatePlan.ScaffoldedPlanReportsSkipped — passed: 3 cases: the skip carries a distinguishable signal — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-6 — test:ValidatePlan.DraftedPlanStillValidated — passed: 2 cases; a missing anchor resolves to drafted (RISK-7) — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-6 — test:ValidatePlan.UnknownStageFailsLoud — passed: RISK-6: an unrecognised stage throws rather than resolving to a skip — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-7 — file:scripts/skalary/Build-Registry.ps1#contains:StringComparer — passed: Build-Marketplace.ps1 and the Test-Registry.ps1 drift gate carry the same ordinal comparer — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-7 — test:BuildRegistry.CzechCollationFixtureIsStable — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-7 — test:BuildRegistry.FixtureIsRedBeforeFix — passed: the fixture still collates chata/cukr/hrad differently between cs-CZ and en-US — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-8 — test:Validate.DotPrefixedPayloadEnumerated — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-8 — test:Validate.GitDirectoryNotEnumerated — passed: RISK-5 negative case, reparse points rejected rather than followed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-8 — test:Validate.FileCountEqualAcrossPlatforms — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.InvokesRunUnitTests — passed: one job, two-OS matrix, separate named steps, no Invoke-Pester — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.DeclaresLeastPrivilege — passed: top-level permissions is exactly contents: read; persist-credentials false; trigger stays pull_request — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.ActionsAndModulesPinnedWithoutSkipPublisherCheck — passed: SHA-pinned actions, exact NuGet range, -AuthenticodeCheck restored, global PSGallery trust removed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.ArtifactNamePerPlatform — passed: per-OS NUnit path and artifact name, uploaded if: always() — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-9 — test:Ci.SeededFailureIsRed — passed: the workflow own command exits 1 on a seeded failing tree; the workflow leaves no way to swallow it — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-10 — file:docs/design-notes/project/ci-gates.design.md#exists — passed — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
✓ REQ-10 — test:CiGates.InventoryMatchesWorkflow — passed: both directions, across the workflow and validate.ps1; excluded gates carry a typed exclusion id naming the decision — 1820cbb672fe375c43f3f44f18d187e1a9a6c6ec
Risks: 14/14 mitigated
✓ RISK-1 — mitigated by steps 2.2 and 3.3: each case gets its own copy under a fresh random root that fails hard if it exists, and test:SuiteOrdering.RandomisedOrderGivesIdenticalResults detects ordering dependence
✓ RISK-2 — mitigated by steps 1.2 and 3.3: test:SuiteCoverage.TestNameInventoryPreserved is a subset assertion and test:SuiteCoverage.ConfinementCasesRetained names the must-keep set
✓ RISK-3 — mitigated by step 5.1: the failure names the install command, and 003 REQ-15 keeps the devcontainer supplied
✓ RISK-4 — mitigated by steps 4.1, 4.2 and 8.3: budgets measured on the CI runners themselves, 3x/2x headroom, per-leg timeout-minutes above each ceiling. The 10x platform gap became 2.05x, so the D13 tier split was not needed
✓ RISK-5 — mitigated by step 7.3: payload roots are an allowlist, canonicalised, reparse points refused (test:Validate.GitDirectoryNotEnumerated)
✓ RISK-6 — mitigated by step 6.1: test:ValidatePlan.UnknownStageFailsLoud
✓ RISK-7 — mitigated by step 6.3: a missing anchor means drafted (test:ValidatePlan.DraftedPlanStillValidated)
✓ RISK-8 — mitigated by step 8.3: test:Ci.DeclaresLeastPrivilege and test:Ci.ActionsAndModulesPinnedWithoutSkipPublisherCheck
✓ RISK-9 — mitigated by step 9.3: the budget was re-run against the final tree at 762 tests, so the figure the operator reads is the last one, not a mid-plan measurement
✓ RISK-10 — mitigated by steps 8.2 and 9.1: every gate is its own named step, and test:Ci.SeededFailureIsRed requires the enforcing command to be the last statement in it
✓ RISK-11 — mitigated by step 2.1: the minimal synthetic fixture landed before the per-case copy; the phase 2 row records 8.775s -> 1.827s
✓ RISK-12 — mitigated by step 2.1: test:SuiteFixture.CarriesTagsForVersionResolution
✓ RISK-13 — mitigated by step 9.2: cluster C is recorded as deferred to 34088e and pinned by test:CiGates.ClusterRetirementIsRecorded
✓ RISK-14 — mitigated by step 4.2: the hatch was not used, CeilingRaises is empty on both platforms, and test:SuiteBudget.CeilingCannotBeRaisedWithoutJustification plus test:SuiteBudget.AbsoluteCapIs900 police it

