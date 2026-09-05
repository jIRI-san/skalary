# Recent learning

Source plan: `33a78a ai-credit-budget-optimization`
Source commit: `41d370d225044e8539e2a2e11a5eaa22bd40e70b`

## Lessons

- Validate operator-selected models at the launcher boundary before setup or authentication side effects. — `plugins/autopilot/scripts/launch.ps1`
- Prefer deterministic graders for observable eval behavior and reserve prompt judges for subjective criteria. — `docs/design-notes/architecture/plugin-evals.design.md`
- Treat default context as a fixed cost boundary and remove override plumbing rather than documenting an expensive option. — `plugins/autopilot/schemas/autopilot.schema.json`
- Regenerate registry and dogfood surfaces whenever canonical plugin payloads change. — `scripts/skalary/Sync-Dogfood.ps1`
