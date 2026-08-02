@{
    # Runtime budget for the repo's test gate. Bound in phase 1 of plan 768d7b — before any
    # optimisation — so later work cannot redefine success by measuring itself.
    Schema = 'skalary/suite-budget@1'

    # The budget measures the whole `npm test` command, not the Pester leg alone: the
    # operator's bar and the recorded baseline are both for `npm test`.
    MeasuredCommand = 'npm test'
    MeasuredLegs = @('validate-plan', 'test:unit', 'validate.ps1')

    # BoundCeilingSeconds is the ceiling agreed at the start and is immutable: it is what
    # HardCeilingSeconds is checked against, so the ceiling can be tightened at will but
    # never quietly loosened.
    BoundCeilingSeconds = 600
    HardCeilingSeconds = 600
    TargetSeconds = 480

    # The single documented escape hatch: step 4.2 may raise HardCeilingSeconds once, to at
    # most AbsoluteCapSeconds, and only with a justification recorded in the plan's
    # assets/decisions.md. CeilingRaises stays empty unless that hatch is used.
    AbsoluteCapSeconds = 900
    MaxCeilingRaises = 1
    JustificationPlanId = '768d7b'
    CeilingRaises = @()
}
