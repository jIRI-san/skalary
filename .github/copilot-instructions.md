# GitHub Copilot Instructions


## "Update Docs" Command

When the user says **"update docs"**:

1. Analyze what was implemented or changed.
2. Update `docs/design-notes/` — existing docs and new ones for new subsystems. Follow conventions in `.design-notes.md`.
3. When updating `project-description.design.md`, sync `README.md` too.
4. Update this file if project status or structure changed significantly.

## Communication Style

- Short and concise. Fragments OK.
- No filler words: just, really, basically, actually, simply
- No pleasantries: sure, certainly, of course, happy to
- No hedging
- Short synonyms: big not extensive, fix not "implement a solution for"
- Technical terms exact
- Code blocks unchanged
- Errors quoted exact

**Do NOT apply** when: warning about security, confirming irreversible actions, multi-step sequences where fragment order risks misread, user is confused.

## Operator Choices and Commands

- For predefined choices, build one ordered option list. Every option includes its consequence, any
  recommendation/default, `effort: <1-10>`, and `complexity: <1-10>`.
- In VS Code, pass that list to `vscode_askQuestions`. In Copilot CLI, render the same labels and
  context as a numbered list and accept the number or exact label. Never stop only because the VS Code
  picker is unavailable. Free-form questions are unchanged.
- Invoke installed scripts directly by stable repo-relative path with bound arguments. Never wrap
  `.github/skills/**` scripts in `pwsh -File` or `powershell -File`. Read-only and focused script paths
  may be pre-approved; mutating scripts remain explicit.
- `/cr` treats violations of these cross-host choice and direct-command rules as findings.

## Design Notes

Detailed patterns and implementation guidance in `docs/design-notes/`. The root index file is always loaded first.

The **architecture-notes** tier (`docs/architecture-notes/`) is a deliberate second always-on index, sitting **above** design notes: interface-level, unbreakable contracts + active ADRs (the *what* and the boundaries), versus implementation-level design notes. Loading **both** indexes is an intentional, documented divergence from the single-index strategy — the per-run token cost is accepted because always-on architecture context materially improves reasoning over complex codebases. The architecture-notes tier is scaffolded on demand; its instruction is a no-op until the tier exists. See `docs/design-notes/project/copilot-customizations.design.md`.

<instructions>
<instruction>
  <description>Always load first — root design-note index, governance rules, and directory of all available design notes with their scopes. Load before any implementation, documentation, or design work.</description>
  <file>docs/design-notes/.design-notes.md</file>
</instruction>
<instruction>
  <description>Architecture-notes tier index (interface-level contracts + active ADRs, above design notes). Load when it exists, before implementation or design work that touches architectural boundaries; a plan/change that violates a locked contract is an architectural finding.</description>
  <file>docs/architecture-notes/.architecture-notes.md</file>
</instruction>
</instructions>
