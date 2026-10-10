# Domain Model

## Terms and meanings

- Preparation HEAD: verified clean implementation commit `1e0be7cac04e0212406a7325929859bd27d9a2ba`, before any fixture mutation.
- H0: future clean source commit after this fixture's own planning-confirmation commit. Not the preparation HEAD or native fixture H0.
- H1: accepted independent source plus exact imported usage. Hhuman: distinct human 1.1 authorization commit. H2/H3: accepted dependent/second results. Hfinal: accepted finalization plus archived ledger.
- Source ref: `jiri-san-docker-ci-acceptance`; worker refs are unique visit-bound refs, not source or PR refs.
- Exit 42: operator action/partial, not closure. Exit 43: rebundle request, not success. Other nonzero exits: inspect/preserve failure.

## Actors and boundaries

- Parent/operator: owns approvals and live 6.2 verdict.
- App coordinator cd67998b-3b75-4933-a7ac-51c2500f4604: admission, exact source, runtime invocation, inspection, decision handoff, verified local fast-forward; no human self-approval.
- Owned transport checkout: separate exact-head Git checkout; launch/config and verified worker-head usage import. No simultaneous integration mutation.
- Docker runtime: fresh named container and one real CLI target; no native child-session claim, PR, legacy loop, or recursive coordinator.

## Interfaces and ownership

- Installed `launch.ps1` receives explicit source/work refs/full expected HEAD, environment and one phase/finalization target.
- Installed `Test-AppCiWorkerResult.ps1` checks mechanical acceptance; actual diff/current evidence and current review remain separate.
- Installed `Record-AiCreditUsage.ps1` imports exact external CLI sidecars at the inspected result HEAD and re-resolves archive layout.
- The package companion is a proposed separate repository using only approved fixture-authored inputs and installed payload, not a subtree npm rebundle or modified Skalary package.

## Invariants

- No implementation parent mutation or smoke import into its branch.
- Source stays fixed during every worker interval. Initial attempt equals current expected HEAD; retry may have a new work HEAD but retains original source ancestry.
- Workers change only fixture source, allowed progress/decisions, then required learning/archive; no human mark or criteria mutation.
- Planning confirmation, operational permission, human 1.1, publication, and parent 6.2 acceptance are different decisions.
