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

## Runtime correction evidence (2026-10-10)

- Operator explicitly retained container and Windows Sandbox autopilot and accepted CLI as their internal worker while using the app to initiate/coordinate.
- `plugins/autopilot/scripts/{launch-container.ps1,container-entrypoint.sh,launch-sandbox.ps1}`: current Docker and Windows Sandbox paths launch CLI phase/completion targets and preserve output, exit, feed/auth and usage mechanisms.
- https://docs.github.com/en/copilot/how-tos/github-copilot-app/agent-sessions : the app is built on Copilot CLI; client interaction is distinct from internal runtime.
- https://docs.github.com/en/copilot/concepts/security-governance-and-network-settings/about-cloud-and-local-sandboxes : app local sandboxing is OS process/filesystem/network containment, not a separate Docker container or Windows Sandbox VM.
- https://code.visualstudio.com/docs/agents/concepts/agent-harnesses : the modern Copilot harness uses the shared SDK across VS Code/CLI/app; shared harness does not establish identical client tools or environment capabilities.
- https://code.visualstudio.com/docs/agents/concepts/agent-host : clients may contribute tools separately from the Agent Host's baseline. VS Code Dev Container capability is not proof of this app's native container/Sandbox attachment.
- https://code.visualstudio.com/docs/agents/run/agents-window : modern VS Code exposes full Agent Host sessions and Dev Container environment selection; Dev Container sessions work in their container workspace and cannot be combined with New Worktree. This is not proof of model-callable automated session creation or a replacement for the retained runtime.
- Operator-selected follow-on requirement: support app and modern VS Code Copilot, verify native full-session capabilities instead of assuming shared tools, and add explicit live VS Code acceptance. Legacy Local extension-host compatibility is not promised.
