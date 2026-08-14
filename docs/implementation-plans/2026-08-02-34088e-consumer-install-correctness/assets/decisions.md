# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Test the installed shape, not the source tree.** Consumer fixtures must contain only declared installed payloads and first-use scaffolds.
- **Keep installer confinement.** Rejected: post-install writes outside `.github/`; runtime owners materialize declared scaffolds on first use.
- **Carry Cluster C explicitly.** The invocation cap, plan-size thresholds, and phase-budget default must derive from or be checked against canonical values; this handoff was previously dropped once.
- **Distribution is part of correctness.** Payload, bundles, dogfood, manifests, marketplace, and registry updates are one change, not optional packaging follow-up.
- **Fail loud on undeclared runtime dependencies.** Missing assets or source-tree fallbacks must not degrade into partial consumer behavior.
