# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **D1 — Narrowly supersede `b0c0d3` REQ-18's object-only/pure-formatter boundary.** Deterministic script-owned collation remains; JSON file ingestion and script-owned output writes replace generated PowerShell because the old invocation made reviewer data executable and unapprovable. See [decisions/review-run-contract.md](decisions/review-run-contract.md).
- **D2 — Versioned authority:** schema `$id` is a repository URL and envelope discriminator is `skalary/review-run@1`; preserved canonical JSON is the source of truth and both Markdown views are digest-bound derivatives. v1 is immutable after release; follow-ups consume it or introduce v2 plus migration.
- **D3 — Closed capacity:** 2 MiB input, 128 tasks, 256 raw findings, 128 merged groups, 160-character titles, 4 KiB bodies, and 8 references per finding. Unknown versions and excess fail closed.
- **D4 — Frozen task truth:** `Freeze` commits at least one unique concern/model task slot before dispatch. `Publish` accepts the exact frozen set with outcomes `completed`, `failed`, `timed-out`, `omitted`, `cancelled`, or `pending`; only all-completed is clean and every other valid mix is degraded.
- **D5 — Bounded dual rendering:** summary is at most 32 KiB and names every merged finding; full Markdown is at most 1 MiB and carries every task/merged finding; raw records remain lossless in JSON.
- **D6 — Byte-budget admission, never truncation:** structural maxima do not promise renderability. `Publish` renders exact UTF-8 bytes first and rejects any envelope that cannot produce both complete views before the manifest changes.
- **D7 — Fixed CLI and exits:** one installed CLI exposes only `Freeze` and `Publish`, computes all paths/schema itself, and returns `0` clean, `5` valid-degraded after publication, `2` invalid, `3` admission/bound, or `4` lock/publication/unexpected.
- **D8 — Independent discovery is invariant:** deduplicate only at render time, never prime or suppress reviewer dispatch based on another reviewer's output.
- **D9 — Model claims stay precise:** v1 records the declared dispatch model, not an unverifiable served identity; current exact-roster elevation behavior stays compatible until `ca8ba8` reviews corroboration semantics.
- **D10 — Ownership order:** `c21cdc` owns v1 validation, persistence, derived attendance, and rendering; `8a0644` depends on it and later owns fleet task-plan production; `ca8ba8` depends on it and owns later similarity/corroboration policy.
- **D11 — Execution:** container autopilot runs the whole plan with no new third-party packages; one final `@human` review gate approves the trust boundary and rendered artifacts.
- **D12 — Native schema validation:** use built-in `Test-Json -SchemaFile` with only draft-2020-12 features proven on the minimum PowerShell capability fixture; semantic and UTF-8 byte rules remain explicit PowerShell checks.
- **D13 — Manifest publication:** immutable content-addressed canonical JSON/summary/full files become visible only through an atomically replaced `review-run.manifest.json`; readers ignore unreferenced files.
- **D14 — Computed artifact homes:** plan runs use `<plan>/assets/reviews/<uuid>/`; generic runs use gitignored `.github/.skalary/review-runs/<uuid>/`. The CLI accepts no schema or output-root parameter.
- **D15 — Canonical bytes:** canonical data is NFC, LF, UTF-8 without BOM, integer-only, ordinal-keyed, and deterministically sorted where arrays are semantically sets; its digest, not raw input ordering, binds every view.
