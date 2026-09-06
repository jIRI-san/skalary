## Source

3a702e8488478dafafef718a7ee57d5bc826ee29

## Scope

- Range e40d1eff653356d265fce0d07db962d70b27e2c2..3a702e8488478dafafef718a7ee57d5bc826ee29; commits 5003417717957baaaaf1e330e4aedd7ecff990fd and 3a702e8488478dafafef718a7ee57d5bc826ee29
- .github/plugin/marketplace.json
- .github/skills/install-plugin/scripts/Install-Plugin.ps1
- .github/skills/install-plugin/scripts/_Common.ps1
- .github/skills/list-plugins/scripts/Get-Plugin.ps1
- .github/skills/list-plugins/scripts/_Common.ps1
- .github/skills/uninstall-plugin/scripts/Remove-Plugin.ps1
- .github/skills/uninstall-plugin/scripts/_Common.ps1
- .github/skills/update-plugin/scripts/Update-Plugin.ps1
- .github/skills/update-plugin/scripts/_Common.ps1
- README.md
- docs/implementation-plans/705e6c-2026-09-03-623cc2-simple-plugin-lifecycle/plan.md
- plugins/plugin-manager/plugin.json
- plugins/plugin-manager/skills/install-plugin/scripts/Install-Plugin.ps1
- plugins/plugin-manager/skills/install-plugin/scripts/_Common.ps1
- plugins/plugin-manager/skills/list-plugins/scripts/Get-Plugin.ps1
- plugins/plugin-manager/skills/list-plugins/scripts/_Common.ps1
- plugins/plugin-manager/skills/uninstall-plugin/scripts/Remove-Plugin.ps1
- plugins/plugin-manager/skills/uninstall-plugin/scripts/_Common.ps1
- plugins/plugin-manager/skills/update-plugin/scripts/Update-Plugin.ps1
- plugins/plugin-manager/skills/update-plugin/scripts/_Common.ps1
- registry.json
- schemas/receipt/receipt.schema.json
- schemas/retirement/removal-journal.schema.json
- schemas/retirement/retirement-state.schema.json
- scripts/skalary/Install-Plugin.ps1
- scripts/skalary/_Common.ps1
- tests/ConsumerInstallFixture.psm1
- tests/skalary/ConsumerInstall.Tests.ps1
- tests/skalary/PluginRetirement.Tests.ps1
- tests/skalary/Skalary.Tests.ps1

## Completed tasks

- [x] Direct lifecycle correctness review: install, update, remove, retirement, minimal receipts, and receipt-last behavior — complete
- [x] Confinement and destructive-operation review with targeted executable repros — complete
- [x] Generated plugin-manager copy and external catalog convergence review — complete
- [x] Focused lifecycle, consumer-install, bundle, marketplace, and residual-retirement test execution — complete

## Findings

- Security — attacker/input: [P1] A plugin registry manifest can supply a destination such as ./workflows/injected.yml.; capability: plugins/plugin-manager/skills/install-plugin/scripts/_Common.ps1:310-320 checks only the first raw segment for workflows, after which Install-Plugin.ps1:253-269 resolves and stages the normalized path.; asset: The consumer repository .github/workflows tree and the CI execution/token boundary it controls.; impact: A targeted install probe exited 0 and wrote .github/workflows/injected.yml, so plugin-controlled workflow code can be installed despite the mandatory workflow refusal.
- [P1] Materialize the receipt ref for local-source removal — plugins/plugin-manager/skills/uninstall-plugin/scripts/_Common.ps1:942-956 assigns the current local checkout directly when its path identity matches, while only the GitHub branch checks out receipt.ref; lines 961-995 then derive deletion authority from that live checkout and delete the receipt. In a targeted repro where the source moved from old.txt to new.txt at the same version after installation, removal reported success, left old.txt installed, and deleted the receipt, defeating exact pinned-manifest removal and receipt-last convergence.
- [P1] Reject duplicate destinations before applying an install — plugins/plugin-manager/skills/install-plugin/scripts/Install-Plugin.ps1:237-291 computes destination keys but never detects duplicates across pending plugins, then lines 294-317 write every operation and lines 343-370 issue every receipt. A targeted two-plugin dependency repro with one shared destination exited 0, left the second payload at that path, and wrote both receipts, falsely recording one corrupted installation as successful.
- [P1] Treat a non-file object at a manifest destination as a conflict, not as missing — plugins/plugin-manager/skills/uninstall-plugin/scripts/_Common.ps1:972-996 uses Test-Path -PathType Leaf both for preflight and deletion, so an existing directory is counted as missing, survives removal, and is followed by receipt deletion. The targeted repro returned RemovedCount=0 and MissingCount=1 while leaving the directory and deleting the receipt; the same leaf-only pattern at Update-Plugin.ps1:102-110 can advance a receipt while an obsolete path remains.
- [P1] Normalize documented owner/repository shorthand before invoking Git in the updater — plugins/plugin-manager/skills/update-plugin/scripts/Update-Plugin.ps1:19-32 validates jIRI-san/skalary as a GitHub identity but passes that unchanged string to git ls-remote, although plugins/plugin-manager/skills/update-plugin/SKILL.md:30 is the shipped default invocation. git ls-remote jIRI-san/skalary main fails as a nonexistent local repository, so the normal bundled update command cannot resolve its source.
- [P1] Do not declare install/update up to date without proving identity and payload state — plugins/plugin-manager/skills/install-plugin/scripts/_Common.ps1:920-925 compares only receipt.version, ignoring sourceIdentity and ref, while plugins/plugin-manager/skills/update-plugin/scripts/Update-Plugin.ps1:77-82 exits on matching version/ref without verifying payload files. Targeted probes showed a same-version install from source B returning success while retaining source A and a same-ref update returning success while leaving a modified payload, violating source-mismatch refusal and convergent retry.
- [P1] Rewrite or remove the remaining retirement-state suite with the retired machinery — tests/skalary/ArchitectureTestRetirement.Tests.ps1:94-101 still calls Invoke-PluginRetirementReconciliation, and lines 139, 173, 189, and 221 exercise it after the implementation removed that command; lines 245-260 also retain the old exit-20 protocol. A focused run discovered 7 tests and failed 5 (four CommandNotFoundException failures plus the obsolete exit-code assertion), so the claimed closed test rewrite leaves directly affected retirement evidence broken.
- [P2] Physically reject linked source payload paths — plugins/plugin-manager/skills/install-plugin/scripts/_Common.ps1:350-397 performs only lexical source confinement, and Install-Plugin.ps1:261-269 feeds the resulting path to Git canonicalization without a link check. A targeted source symlink pointing outside the plugin root installed the external file bytes and exited 0, so manifest-owned payload is not actually confined to the plugin snapshot as required.

## Verdict

findings
