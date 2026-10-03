# References

- User discussion and explicit MVP choices in this session, 2026-10-03.
- `docs/design-notes/.design-notes.md` and `docs/architecture-notes/.architecture-notes.md`.
- `docs/design-notes/project/simplicity-first.design.md`: local fixes and single-operator scope.
- `docs/design-notes/project/ci-gates.design.md`: local focused validation, no hosted workflows.
- `docs/design-notes/architecture/plan-workflow.design.md` and
  `docs/architecture-notes/arch-direct-workflow.md`: confirmation baseline and current evidence.
- `docs/design-notes/architecture/autopilot-execution.design.md`: launchers, recovery and usage.
- `docs/design-notes/architecture/plugin-registry.design.md` and
  `docs/design-notes/architecture/plugin-manager.design.md`: packaging, marketplace and installed closure.
- `docs/architecture-notes/arch-install-confinement.md`: installer versus first-use scaffold boundary.
- `docs/design-notes/architecture/plugin-evals.design.md` and
  `docs/architecture-notes/arch-eval-gate-separation.md`: offline/premium split and write-isolation caveats.
- `plugins/create-implementation-plan/skills/cip/SKILL.md` and its decision, review and template assets.
- `scripts/skalary/{New-Plan,Set-PlanStage,Test-Plan}.ps1` and `PlanState.psm1`: plan authoring owners.
- `scripts/skalary/DirectWorkflow.psm1`, `EpicAutopilot.psm1` and `Invoke-EpicAutopilot.ps1`:
  current evidence, retained checkpoints and explicit operator-merge boundary.
- No historical plan loaded; current implementation and active contracts suffice for this new subsystem.
