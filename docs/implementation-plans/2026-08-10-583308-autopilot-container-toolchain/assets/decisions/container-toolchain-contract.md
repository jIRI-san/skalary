# Container toolchain contract

This decision is now maintained as a durable design note so it outlives the plan folder:

**[docs/design-notes/architecture/autopilot-container-toolchain.design.md](../../../../design-notes/architecture/autopilot-container-toolchain.design.md)**

The approved baseline table, acquisition boundary, smoke schema, attestation rules, gate outcomes,
and control-plane bootstrap behaviour live there and are read directly by
`test:AutopilotContainer.ToolchainContract`. A plan folder is archived when the plan completes; a
contract whose enforcing test points into it would silently stop being enforced at that moment.
