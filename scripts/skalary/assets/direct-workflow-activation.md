# Direct workflow consumer activation map

**DORMANT — Step 2.2 only.** No active skill, agent, plugin manifest, catalog, or dogfood payload
references this file or the targets it inventories.

## Target replacements

| Consumer | Dormant canonical target | Step 2.2 active destination |
|---|---|---|
| CR | `plugins/code-review/skills/cr/targets/direct/SKILL.md` | `plugins/code-review/skills/cr/SKILL.md` |
| DR | `plugins/design-review/skills/dr/targets/direct/SKILL.md` | `plugins/design-review/skills/dr/SKILL.md` |
| CEP | `plugins/create-implementation-plan/skills/cep/targets/direct/SKILL.md` | `plugins/create-implementation-plan/skills/cep/SKILL.md` |
| CIP | `plugins/create-implementation-plan/skills/cip/targets/direct/SKILL.md` | `plugins/create-implementation-plan/skills/cip/SKILL.md` |
| CI | `plugins/continue-implementation/skills/ci/targets/direct/SKILL.md` | `plugins/continue-implementation/skills/ci/SKILL.md` |
| autopilot skill | `plugins/autopilot/skills/autopilot/targets/direct/SKILL.md` | `plugins/autopilot/skills/autopilot/SKILL.md` |
| autopilot agent | `plugins/autopilot/agents/targets/direct/autopilot.agent.md` | `plugins/autopilot/agents/autopilot.agent.md` |

## Canonical script closure

Canonical scripts remain single-sourced under `scripts/skalary/`. `Sync-PluginScripts.ps1` derives
these sibling closures after the target instructions become active:

| Entry point | Closure | Installed consumers |
|---|---|---|
| `DirectWorkflow.psm1` | `DirectWorkflow.psm1`, `PlanState.psm1`, `SecretGuard.psm1` | `cr`, `dr`, `ci`, `autopilot` |
| `Get-DirectPlanArtifactConsumerContext.ps1` | `Get-DirectPlanArtifactConsumerContext.ps1`, `DirectWorkflow.psm1`, `PlanState.psm1`, `SecretGuard.psm1` | `cr`, `dr`, `cep`, `cip` |

Do not hand-copy module logic. Add each applicable canonical entry point and its derived closure to the
owning plugin manifest only during Step 2.2.

## Exact Step 2.2 activation

1. Replace the seven active canonical plugin files with the target files above; remove the now-consumed
   target directories.
2. Add the two canonical script entry points and derived closures to the listed plugin manifests.
3. Delete the superseded ReviewRun, Fleet, receipt/evidence-receipt, review-cycle, generated-concern,
   harvest/repair, and historical receipt-validation payloads and their manifest entries in the same
   working tree.
4. Run `scripts/skalary/Sync-PluginScripts.ps1`, then `scripts/skalary/Build-Registry.ps1`.
5. Run `scripts/skalary/Sync-Dogfood.ps1` only after all canonical targets and manifests are switched;
   this is the first point at which `.github/skills/**` and `.github/agents/**` may receive direct paths.
6. Run focused direct-consumer install and retired-residue tests before committing. Do not retain a
   compatibility flag, dual authority, or fallback to the legacy workflow.
