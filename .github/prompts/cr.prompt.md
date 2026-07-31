---
description: "Code review — reviews uncommitted changes, unpushed commits, last N commits, or specific files/folders. Usage: /cr [uncommitted|branch|N|N batch|path ...]"
name: cr
agent: cr
---

# /cr

Thin shortcut. The full, CLI-standalone workflow lives in the **cr** skill
([SKILL.md](../skills/cr/SKILL.md)) — this prompt only passes the argument through.

1. Read the cr skill and note the argument after `/cr`: `${input}`.
2. Run the skill end to end with that argument; an empty argument means the branch-aware default.
