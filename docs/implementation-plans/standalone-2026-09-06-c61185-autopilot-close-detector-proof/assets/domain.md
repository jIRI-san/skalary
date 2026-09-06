# Domain Model

<!-- Capture project-specific terms, actors, invariants, and boundaries that affect the design. -->

## Terms and meanings

- **Proof file** — disposable text file created only to give autopilot an observable implementation step.
- **Terminal close** — archived clean plan plus exact-head pull-request proof classified as `closed`.

## Actors and boundaries

- The container autopilot owns implementation, validation, archival, publication, and close detection.
- The host observes the exit code and transcript, then removes throwaway artifacts.

## Interfaces and ownership

- `plan.md` owns execution state.
- `tests/autopilot-close-detector-proof.txt` owns the disposable observable result.

## Invariants

- The proof pull request stays unmerged.
- No production source is changed by the throwaway plan.
