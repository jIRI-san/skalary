# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Standalone instruction-first `/ws` plugin | Invocable skill/installed asset closure; no new runtime scripts or review dependency; `test:Workshop.Payload` | 1.1, 2.1 |
| REQ-2 | Focused interview and approved alternative set | Distinct concept sketches, lifetime cap of three including replacements, scoped demos/tradeoffs; set/replacement approval before launches and selection after inspection; `test:Workshop.Scope` | 1.1, 1.2 |
| REQ-3 | Integrated runnable central slice | Real insertion/connection points, peripheral stubs disclosed, focused validation only, blocked variants visible; `test:Workshop.VerticalSlice` | 1.1, 1.2, 2.2 |
| REQ-4 | Comparable isolation across app, VS Code, CLI | Same recorded SHA; dirty-base decision; isolated edits/outputs/ports; native sessions or direct Git route, explicit unavailable-host stop; `test:Workshop.Isolation` | 1.1, 1.2, 2.2 |
| REQ-5 | Inspection teaches shape and surrounding code | UI previews/layouts; component interface/usage examples; each variant has entrypoints, connections, insertion points, touched codepaths, demo/check, gaps; `test:Workshop.IntegrationMap` | 1.1, 1.2, 2.2 |
| REQ-6 | Operator-selected draft CIP starting point | Selected branch/worktree/commit retained; explicit self-contained handoff sent to selected app session or pasted with CIP in VS Code/CLI, including rationale/maps/gaps; reconfirmation/redesign allowed; mismatches stop; `test:Workshop.CipHandoff` | 1.2, 2.2 |
| REQ-7 | Exploration remains lightweight and retained | No prototype review/evidence/formal-plan lifecycle, broad tests, auto-merging/publication/deletion; `test:Workshop.Selection` | 1.1, 1.2 |
| REQ-8 | Distribution and docs stay consistent | Register plugin plus existing consumer-smoke switch arm atomically; registry/mirrors/marketplace/README generated through existing tools; guide inventory/links and design notes updated; `test:Workshop.ConsumerSmoke`, `file:docs/operator-guide/workshop.md#exists`, `file:docs/design-notes/architecture/workshop.design.md#exists` | 1.1, 2.1, 2.2 |
