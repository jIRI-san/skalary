@{
    Schema = 'skalary/suite-tier@1'

    # Slow has its own wall-clock ceiling. It is separate from the Fast/npm-test budget,
    # but still bounded so moving work out of Fast cannot create an unlimited gate.
    SlowHardCeilingSeconds = 1800
    SlowMeasurementRecord = 'tools/suite-slow-runtime.json'

    # Scheduling reservation for module setup, evals, review-consumer execution, and
    # diagnostics around the two bounded tiers.
    CiSetupAllowanceSeconds = 900

    # This matrix already has its own blocking runner and NUnit artifact.
    DedicatedFiles = @(
        'tests/skalary/ReviewConsumerInstall.Tests.ps1'
    )

    # Process-heavy integration suites. Fast is the derived complement, so a new
    # test file cannot silently disappear: it starts in Fast until deliberately moved.
    SlowFiles = @(
        'tests/skalary/Add-LedgerEntry.Tests.ps1'
        'tests/skalary/ArchitectureRetirementBaseline.Tests.ps1'
        'tests/skalary/ArchitectureTestRetirement.Tests.ps1'
        'tests/skalary/AssetBootstrap.Tests.ps1'
        'tests/skalary/AutopilotContainerGate.Tests.ps1'
        'tests/skalary/Ci.Tests.ps1'
        'tests/skalary/ConsumerInstall.Tests.ps1'
        'tests/skalary/PlanAssets.Tests.ps1'
        'tests/skalary/PluginRetirement.Tests.ps1'
        'tests/skalary/ReviewReportCorpus.Tests.ps1'
        'tests/skalary/ReviewReportDiscovery.Tests.ps1'
        'tests/skalary/ReviewRunArtifacts.Tests.ps1'
        'tests/skalary/ReviewRunBudget.Tests.ps1'
        'tests/skalary/ReviewRunEncoding.Tests.ps1'
        'tests/skalary/ReviewRunFreeze.Tests.ps1'
        'tests/skalary/ReviewRunManifest.Tests.ps1'
        'tests/skalary/ReviewRunPublish.Tests.ps1'
        'tests/skalary/ReviewRunSchema.Tests.ps1'
        'tests/skalary/ReviewScope.Tests.ps1'
        'tests/skalary/RunUnitTests.Tests.ps1'
        'tests/skalary/SiWriteScope.Tests.ps1'
        'tests/skalary/Skalary.Tests.ps1'
        'tests/skalary/SuiteBudget.Tests.ps1'
        'tests/skalary/SuiteFixture.Tests.ps1'
        'tests/skalary/SuiteOrdering.Tests.ps1'
    )
}