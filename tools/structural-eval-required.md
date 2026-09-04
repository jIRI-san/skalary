# Required structural evals

The direct operator-only full-repository eval command requires every case below to run exactly once
and pass. Keep one literal ``- `eval:...` `` entry per line; the runner rejects duplicates, missing
entries, and any other list syntax.

- `eval:ReviewReport.CR.WriterScope`
- `eval:ReviewReport.CR.FreezeBeforeDispatch`
- `eval:ReviewReport.CR.IndependentDispatch`
- `eval:ReviewReport.CR.CompleteDispatch`
- `eval:ReviewReport.CR.NonzeroTaskPlan`
- `eval:ReviewReport.CR.RendererOwnedMarkdown`
- `eval:ReviewReport.CR.FixedPolicyAndRoot`
- `eval:ReviewReport.CR.DegradedArtifactPreservation`
- `eval:ReviewReport.CR.BoundedRetry`
- `eval:FleetDispatch.CIP.ConsumerContract`
- `eval:FleetDispatch.CI.ConsumerContract`
- `eval:FleetDispatch.Autopilot.ConsumerContract`
- `eval:FleetDispatch.CR.ConsumerContract`
- `eval:FleetDispatch.DR.ConsumerContract`
- `eval:ReviewReport.DR.WriterScope`
- `eval:ReviewReport.DR.FreezeBeforeDispatch`
- `eval:ReviewReport.DR.IndependentDispatch`
- `eval:ReviewReport.DR.CompleteDispatch`
- `eval:ReviewReport.DR.NonzeroTaskPlan`
- `eval:ReviewReport.DR.RendererOwnedMarkdown`
- `eval:ReviewReport.DR.FixedPolicyAndRoot`
- `eval:ReviewReport.DR.DegradedArtifactPreservation`
- `eval:ReviewReport.DR.BoundedRetry`
