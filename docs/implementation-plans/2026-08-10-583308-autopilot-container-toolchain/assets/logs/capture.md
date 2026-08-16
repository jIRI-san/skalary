## Capture
Phase: 1

- [1.1] [src:note] interview: operator confirmed curated baseline, path-filtered blocking Linux CI, advisory 250 MiB growth threshold, and no Windows Sandbox parity
- [1.2] [src:note] prior-art: reuse plans 001 and 003 container and payload contracts; extend aaf29b image-owned versus runtime-package boundary and 768d7b affordable-gate separation; no conflict or supersede

## Capture
Phase: 2

- [2.1] [src:note] dr: one trusted runner now owns event identity, NUL-safe relevance, path closure, payload parity, candidate-only comparison, bounded receipts, and local-CI replay
- [2.2] [src:note] dr: the gate is post-merge on push-to-main and is always reported there; a pull_request definition is candidate-authored and cannot enforce a boundary against the candidate, and no organization required workflow exists here. Candidate Docker content runs secretless and socketless with durable failure evidence

## Capture
Phase: 3

- [3.1] [src:note] local Measure of 714556e vs base c961786 (origin/main, genuinely pre-toolchain): outcome=success, comparison=candidate-only, reason=base-context-absent, candidateMs=6691, baseMs=0, totalMs=7253, candidateBytes=2856022233, smoke=21 pass with empty reason set, receiptSha256=511925279b0da74f8b0d2eb7bfab7f1a67572731f9a5aaea0c60d17144222c59
- [3.1] [src:note] this entry previously narrated a candidate-only run while the committed receipt recorded a comparable one against b71e7dd; the two described different runs and the receipt's base already contained the toolchain. Both are now the same run against the same base
- [3.1] [src:note] direct two-build image growth measurement (method recorded in image-growth.json): candidate 2856022233 bytes, base 2519751105 bytes, delta 336271128 bytes = 320.69 MiB, which exceeds the 250 MiB advisory threshold
- [3.1] [src:note] real container smoke run of the built candidate image: 21 cases, state=pass, reasons=[], exit 0, manifestSha256 matching the repository's toolchain.tsv; the reason vocabulary was separately driven to a 7-reason failure in a bare debian:trixie-slim container
- [3.1] [src:note] structural eval: candidate and exact f710963 base both passed 116/122 with the same two pre-existing architecture-notes failures; no phase delta
