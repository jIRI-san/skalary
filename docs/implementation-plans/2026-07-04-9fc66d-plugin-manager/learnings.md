## Learnings Capture
Phase: 1

- [1.1] [trigger:reusable-pattern] Sync-PluginScripts moduleRegex needed leading-underscore class ((A-Za-z0-9_)) AND .psm?1 to match _Common.ps1; extension widening alone was insufficient.
- [1.3] [trigger:plan-contradiction] VS Code chat.tools.terminal.autoApprove matches command PREFIX (per user memory: 'invoke .ps1 directly; pwsh -File wrapping breaks auto-approval'). Plan's regex-anchored entries + REQ-2 'pwsh -File' invocation would make approvals never fire. Needs plain path-string keys + direct .ps1 invocation in skills.

## Learnings Capture
Phase: 3

- [3.1] [trigger:reusable-pattern] Spike CONFIRMED: copilot plugin install ./plugins/plugin-manager accepts the shared plugin.json (extra fields files/dependencies/status/evals tolerated), loaded 4 skills, no strict:false needed for direct install. Direct installs deprecated -> marketplace route required; set strict:false on marketplace entries as safeguard.
