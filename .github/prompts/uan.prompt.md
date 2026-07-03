---
description: "Update an architecture note/contract. Thin wrapper over the architecture-notes skill. Usage: /uan <name or boundary>"
name: uan
agent: agent
---

## Update Architecture Note

Thin shortcut. The full, CLI-standalone workflow lives in the **architecture-notes** skill
([SKILL.md](../skills/architecture-notes/SKILL.md)) — this prompt only presets the operation.

1. Invoke the **architecture-notes** skill with operation **update**.
2. Pass the text after `/uan` as the contract/note to update: `${input}`.
3. Follow the skill's Step 3 (update a contract) — never silently rewrite a `locked` contract
   body; propose changes for human review. Re-validate with `Test-ArchContract.ps1`.
