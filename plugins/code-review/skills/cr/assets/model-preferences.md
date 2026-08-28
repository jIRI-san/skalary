# Code-review model preferences

This file is the single editable model policy for `/cr`. Keep model labels in the qualified
`Model Name (vendor)` form accepted by VS Code-hosted subagents.

## Models

| Role | Model | Reasoning effort | Context tier |
|---|---|---|---|
| Primary | `GPT-5.6 Sol (copilot)` | `high` | `default` |
| Secondary | `Claude Opus 5 (copilot)` | `high` | `default` |
| Backup | `Claude Sonnet 4.6 (copilot)` | `high` | `default` |

The backup replaces an unavailable requested model; it is not an additional reviewer pass. Pass the
model, reasoning effort, and context tier as explicit subagent invocation parameters.

## Execution profiles

| Profile | Models | Automatic round cap | Intended caller |
|---|---|---|---|
| `post-phase` | Primary only | 3 | `/ci` and autopilot after every completed implementation phase |
| `plan-finalization` | Primary + Secondary | 3 | `/ci` and autopilot once, after every implementation phase is complete |
| `standalone` | Primary + Secondary | n/a | Direct `/cr` use |

Callers must select the profile explicitly. A direct `/cr` invocation with no profile uses
`standalone`. `plan-finalization` reviews the whole implementation, not only the final phase.
Its primary + secondary review may run up to three rounds before requiring an operator decision.
