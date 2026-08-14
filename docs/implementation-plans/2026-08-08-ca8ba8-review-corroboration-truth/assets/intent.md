# Intent

> Preliminary context captured from the 2026-08-08 comparison discussion for epic `33b1f9`. `/cip` must confirm and refine it.

## Goal

Make review reports state the real corroboration behind each finding instead of treating declared model diversity or near-identical output as independent agreement.

## Desired outcome

The report derives an explicit corroboration regime from observable run data, flags suspiciously similar nominally independent findings, and prevents similarity or degraded model attendance from raising confidence. Declared and observed facts are kept distinct in both machine-readable and rendered output.

## Success signals

- Near-identical outputs from nominally different reviewers are flagged and never counted as independent corroboration.
- Severity elevation requires valid independent attendance and agreement, not only matching declared model labels.
- The report header says whether findings are independently corroborated, single-source, suspicious, or degraded.
- Corroboration state is preserved as data for later consumers and tests.

## Non-goals

- Asking a served model to attest its own identity.
- Priming one discovery reviewer with another reviewer's findings.
- Owning the general review-report envelope already assigned to `c21cdc`.

## Definition of done

- A reader can tell exactly what independent support stands behind every finding, and degraded or suspicious runs can only lower confidence or block elevation.
