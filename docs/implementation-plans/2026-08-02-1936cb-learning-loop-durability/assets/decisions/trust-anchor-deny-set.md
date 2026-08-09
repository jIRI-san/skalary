# SI Trust-Anchor Deny Set

`/si` proposals may edit customization content but may not alter the machinery that confines, validates, transports, or merges their own proposal. `Test-SiWriteScope`, trusted synchronization, and operator completion all reject any touched path in this closed set before considering the broader allowlist:

- `plugins/self-improvement/plugin.json`
- `plugins/self-improvement/scripts/**`
- `plugins/self-improvement/schemas/**`
- `plugins/self-improvement/skills/si/scripts/**`
- `plugins/self-improvement/skills/si/schemas/**`
- `plugins/self-improvement/skills/si/SKILL.md`
- `plugins/self-improvement/skills/si/assets/{harvest-guide,propose-guide}.md`
- `plugins/self-improvement/prompts/si.prompt.md`
- `.github/skills/si/scripts/**`
- `.github/skills/si/schemas/**`
- `.github/skills/si/SKILL.md`
- `.github/skills/si/assets/{harvest-guide,propose-guide}.md`
- `.github/prompts/si.prompt.md`
- `scripts/skalary/Test-SiWriteScope.ps1`

A harvested candidate requiring any denied path becomes an implementation plan, not an SI proposal. `test:SiScope.ProtectedTrustAnchorsAllRefused` iterates every exact file and wildcard member in canonical and installed trees, fails on any canonical/installed asymmetry, and includes one allowed-content control.