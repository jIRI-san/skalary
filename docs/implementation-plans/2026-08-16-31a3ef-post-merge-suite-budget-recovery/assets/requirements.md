# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Post-merge authorities are coherent. | Active CR/DR PlanState bundles are included, archived dependencies are not reported unmet, intended c21cdc removals are recorded, and retired architecture-test runtime residue is absent. `test:PlanEvidence.MarkerTokenizationAndRetiredArch` · `test:Epic.ReviewRunConsumerEdgesAndState` · `test:SuiteCoverage.TestNameInventoryPreserved` · `test:ArchitectureTestRetirement.RuntimeSurfaceAbsent` | 1.1, 2.2, 3.1 |
| REQ-2 | The deterministic suite has one closed, lossless partition. | A tracked manifest owns slow files; every discoverable test file is Fast or Slow with no overlap, while the separately dedicated review-consumer matrix remains excluded from both. `test:SuiteTier.PartitionContract` · `file:tools/suite-tier.psd1#exists` | 1.2, 2.2, 3.1 |
| REQ-3 | Both tiers preserve runner failure semantics. | Fast and Slow use `Run-UnitTests.ps1`; both fail on test/discovery/environment/required-evidence defects; only Fast consumes and enforces the `npm test` budget clock. `test:RunUnitTests.TierExecution` · `test:RunUnitTests.MissingPesterExitsNonZero` | 1.2, 2.1, 2.2, 3.1 |
| REQ-4 | CI requires and attributes both tiers. | Each Linux/Windows matrix leg runs both tiers as blocking steps and publishes separate NUnit reports; inventory and workflow agree. `test:CiGates.InventoryMatchesWorkflow` · `test:Ci.WorkflowSecurityContract` · `review:cr` | 2.1, 2.2, 3.1 |
