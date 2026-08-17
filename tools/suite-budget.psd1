@{
    # Runtime budget for the repo's test gate. Bound in phase 1 of plan 768d7b — before any
    # optimisation — so later work cannot redefine success by measuring itself.
    Schema = 'skalary/suite-budget@2'

    # The budget measures the whole `npm test` command, not the Pester leg alone: the
    # operator's bar and the recorded baseline are both for `npm test`.
    MeasuredCommand = 'npm test'
    MeasuredLegs = @('validate-plan', 'test:unit', 'validate.ps1')

    # Where the achieved figures live. Named here rather than only in the test, so the budget
    # says what it was tightened against and a reader can check the claim.
    MeasurementRecord = 'tools/suite-runtime.json'

    # BoundCeilingSeconds is the ceiling agreed at the start and is immutable: it is what
    # every platform's HardCeilingSeconds is checked against, so a ceiling can be tightened
    # at will but never quietly loosened.
    BoundCeilingSeconds = 600

    # The single documented escape hatch: step 4.2 may raise one platform's
    # HardCeilingSeconds once, to at most AbsoluteCapSeconds, and only with a justification
    # recorded in the plan's assets/decisions.md. CeilingRaises stays empty unless that
    # hatch is used. A platform that still cannot meet its ceiling splits into fast and slow
    # tiers (D13) rather than taking a second raise.
    AbsoluteCapSeconds = 900
    MaxCeilingRaises = 1
    JustificationPlanId = '768d7b'

    # Each reduction phase's declared saving (D4). It is pinned here rather than only in
    # tools/suite-profile.json because that document is rewritten in full by every measuring
    # run: a rerun that simply omitted the target would record a target of zero and turn a
    # missed phase into a passing one. Scoring on an operation's aggregate seconds rather
    # than wall clock keeps a few-second move out of run-to-run scheduling noise.
    PhaseTargets = @{
        # The baseline declares no saving: it is what the later phases are measured against.
        # It is still listed, so that "every recorded phase is declared here" is a total rule
        # with no exempt row a forgotten phase could hide behind.
        '1' = @{
            Scope = 'run'
            BaselineSeconds = 0.0
            RequiredSavingSeconds = 0.0
        }
        '2' = @{
            Scope = 'New-RepoClone'
            BaselineSeconds = 8.775
            RequiredSavingSeconds = 4.4
        }
        # Phase 3 spans two scopes — the Build-Registry calls step 3.1 narrows and the four
        # costliest residue files step 3.2 rewrites — so no single instrumented operation
        # covers it and the run is what it is scored on. The baseline is phase 2's achieved
        # wall clock, the figure phase 3 inherits. The required saving is half the phase-1
        # cost of the four named files (30.575s), floored at 10s: ~10% of a ~96s run, which
        # is far enough above the few-second scheduling noise that made wall clock unusable
        # for phase 2's ~7s move to be decided by the change rather than by the scheduler.
        '3' = @{
            Scope = 'run'
            BaselineSeconds = 95.847
            RequiredSavingSeconds = 10.0
        }
    }

    # The ceiling is per platform (D13): the same suite measured ~10x apart between the
    # Linux container and a Windows host, so one shared number would be either unreachable
    # on Windows or vacuous on Linux. The runner enforces the entry for the platform it is
    # running on; a platform with no entry is an error, not an exemption.
    #
    # Step 4.2 tightened both entries against the figures step 4.1 measured on the runners the
    # gate is enforced on — recorded, with their environment, in tools/suite-runtime.json.
    # Headroom is stated rather than chosen per platform: the hard ceiling is 3x the achieved
    # figure and the target 2x, each rounded up to the next 30s, and neither may exceed the
    # value it is replacing — a ceiling may only fall. The 3x absorbs a runner that is slower
    # or noisier than the one measured without turning ordinary variance into a red build
    # (RISK-4), which is the failure that makes people stop trusting the gate.
    #
    # Achieved (commit c99d5d1, both runs green, both 4-core):
    #   Linux   ci:ubuntu-latest  108.998s -> 3x = 330s ceiling, 2x = 240s target
    #   Windows ci:windows-latest 223.142s -> 3x = 690s, above the 600s it would replace, so
    #           the ceiling stays 600s and only the target falls to 450s.
    # Windows was 1157s when D13 was written; phases 2 and 3 initially brought it to 2.05x Linux.
    # Later review-run coverage raised the complete suite above this Fast ceiling, so plan 31a3ef
    # activated D13's tracked Fast/Slow split without taking a ceiling raise.
    Platforms = @{
        Linux = @{
            HardCeilingSeconds = 330
            TargetSeconds = 240
            CeilingRaises = @()
        }
        Windows = @{
            HardCeilingSeconds = 600
            TargetSeconds = 450
            CeilingRaises = @()
        }
    }
}
