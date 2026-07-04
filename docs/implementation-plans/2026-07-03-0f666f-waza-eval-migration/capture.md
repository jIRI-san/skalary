## Capture
Phase: 1

- [1.4] [src:note] [sev:Med] gh provisioning gap for non-interactive/CI: winget GitHub.cli MSI requires UAC elevation (exit 1602 when unelevated). Ensure-EvalTools gh install cannot complete unattended on Windows. Phase 3 (ADO) + local non-elevated dev must pre-install gh or install from an elevated context; consider a user-scope install path or documenting gh as a prerequisite. Live gh-OAuth entitlement probe (personal + corp SSO orgs) remains OPEN pending interactive 'gh auth login'.
- [1.0] [src:discovery] [sev:Med] copilot-sdk tool-name mapping is OS-dependent for the shell: execute fans out into create/edit + powershell (Windows) / bash (Linux). Autopilot + ADO CI containers are Linux, so 2.4's build/test-before-commit tool_calls grader must branch the shell tool name on OS or it will silently never match (false pass). Recorded in gate (g).
