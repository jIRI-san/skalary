# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

- `plugins/autopilot/devcontainer/Dockerfile` — canonical image definition and current tool inventory.
- `plugins/autopilot/devcontainer/devcontainer.json` — non-root runtime user and Docker socket contract.
- `plugins/autopilot/scripts/launch-container.ps1` — shipped Dockerfile build path and payload source.
- `docs/design-notes/architecture/autopilot-execution.design.md` — container execution, security, and distribution contract.
- `docs/implementation-plans/archived/001-autopilot-execution-infra/plan.md` — prior autopilot container decisions; this plan extends tooling without changing safety rules.
- Plan `003` (`autopilot-skill-extraction`) — reuse plugin-canonical to `.github` dogfood distribution and drift enforcement.
- Plan `aaf29b` (`offline-package-bundling`) — reuse the distinction between image-owned OS tools and runtime NuGet/npm package rebundling; `expected-packages: none` remains correct.
- Plan `768d7b` (`gates-real-and-affordable`) — extend the affordable-gate decision by keeping Docker builds out of `npm test` and limiting them to relevant image-contract paths.
- Epic `33b1f9` — workflow machinery hardening; this child improves autonomous implementation ergonomics and reproducibility.
