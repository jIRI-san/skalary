# References

## Active contracts and design

- `docs/architecture-notes/.architecture-notes.md` and provisional `arch-direct-workflow.md`: criteria baseline, current evidence, bounded reviews, terminal lifecycle; update the execution-host boundary with implementation.
- `docs/design-notes/project/simplicity-first.design.md`: prefer reuse/deletion/local fixes over new execution machinery.
- `docs/design-notes/architecture/{plan-workflow,autopilot-execution,plugin-registry,skalary-config,plugin-evals,review-reporting}.design.md`: current plan/runtime, source/distribution ownership, model/eval and review seams.
- `docs/design-notes/project/copilot-customizations.design.md`: thin host shims and skills as instruction authority.

## Current implementation inspected

- `tools/model-allowlist.psd1`: six public aliases; Routine medium and Standard/Deep/Independent high; explicit host formats and fallback aliases.
- `scripts/skalary/{Sync-ModelBindings,Test-ModelAllowlist}.ps1`: generated model assets, Waza bindings, closed aliases and allowed effort values.
- Installed `Read-SkalaryConfig.ps1 -Action show -Category models-reviews`: confirms source policy authority and generated-only assets.
- `plugins/continue-implementation/{plugin.json,skills/ci/SKILL.md}`: current direct execution and autopilot dependency.
- `plugins/autopilot/{plugin.json,agents/autopilot.agent.md,skills/autopilot/SKILL.md,scripts/launch-host.ps1}`: self-contained runtime and separate per-phase/completion CLI targets.
- `scripts/skalary/{Get-PhaseExecutionState,Invoke-EpicAutopilot}.ps1` and `EpicAutopilot.psm1`: committed phase close and host-only epic launcher/provider proof.
- `registry-retirements.json`: existing published append-only retirement and pinned payload/removal guidance.
- Existing focused tests in `tests/{skalary,autopilot,evals,factory-loop}`: model bindings, phase/epic/runtime/distribution and consumer integration.
- Native app tool schemas: `create_session` supports explicit model, reasoning effort, context, execution mode, source branch, and isolated worktree; native session inspection distinguishes busy, idle and human gates.

## Bounded historical discovery

- Filtered `Get-PlanIndex.ps1` query `app-native|app-only|phase.child|Copilot app|autopilot retirement` found one workshop intent candidate, plan `4e0f9b`, describing cross-host prototype support.
- That workshop commitment is not a CI execution requirement and is not superseded by this change. No historical artifact was loaded as authority; no equivalent earlier app-native CI migration was returned by the bounded query.

## Public host reference

- https://docs.github.com/en/copilot/reference/github-copilot-app-reference/repository-configuration : `.github/github-app.yml` `instructions` adds project guidance after acceptance; it does not define a documented phase-model configuration field. Keep model authority in the existing policy and pass explicit kickoff settings.
- No external pricing claim is required: GPT-6.1 Sol is the operator's selected cost preference.
