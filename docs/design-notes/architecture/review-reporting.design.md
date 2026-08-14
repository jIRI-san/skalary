---
description: The review-run data contract — canonical schemas under schemas/review/, the schema-owned limit vocabulary, the structural/semantic layer split, the PowerShell 7.6 capability preflight and the committed corpus/edge fixtures. Load before touching schemas/review/**, scripts/skalary/Test-ReviewSchemaCapability.ps1, scripts/skalary/Build-ReviewReport.ps1 or tests/skalary/fixtures/review-run/**.
globs:
  - schemas/review/**
  - scripts/skalary/Test-ReviewSchemaCapability.ps1
  - scripts/skalary/Build-ReviewReport.ps1
  - tests/skalary/fixtures/review-run/**
---

# Review reporting

Plan `c21cdc` turns a review run into one versioned data artifact. This note covers what exists
today: the schemas, the capability gate and the fixtures. Publication, canonicalization, rendering
and the `Freeze`/`Publish` CLI are step 1.2 and are described here only where the data contract
already constrains them.

## Artifacts and their schemas

| Schema | Artifact | Written by |
|---|---|---|
| `schemas/review/review-plan.schema.json` | the frozen planned-task set, before any reviewer is dispatched | `Freeze` |
| `schemas/review/review-run.schema.json` | the final `skalary/review-run@1` envelope | `Publish` |
| `schemas/review/review-manifest.schema.json` | the publication commit point, replaced last | `Publish` |
| `schemas/review/terminal-status.schema.json` | the single JSON object every terminal path prints | every mode, including the preflight |
| `schemas/review/review-limits.schema.json` | the shared limit and leaf-type vocabulary | nothing — it is read, never emitted |

`$id` is the repository URL for the file; the envelope discriminator is `skalary/review-run@1`
(D2). Every object is closed, so there is no aggregate property for a caller to supply: counts,
attendance and run state are derived from `tasks`.

## Why the vocabulary is embedded rather than referenced

`review-limits.schema.json` owns every shared definition. The four validation schemas **embed** the
definitions they need and point at them with internal `#/$defs/...` pointers only.

An external `$ref` does resolve on PowerShell 7.6, but step 2.1 distributes these files one at a
time into consumer installs, where a cross-file pointer resolves against a file that may not have
been copied. Self-contained schemas keep each file independently usable; the duplication is held
still by `test:ReviewReport.SchemaCapabilityAndSemantics`, which requires every embedded copy to be
deep-equal to the vocabulary and requires every limit keyword to live inside `$defs` — a `maxLength`
written directly onto a property would be a limit nothing compares.

`x-skalary-limits` carries the numbers no keyword can express (UTF-8 byte budgets, rendered view
sizes, the lock timeout). The same test pins them against the `$defs` they mirror.

## The structural/semantic split

The schema decides structure, closedness, vocabularies, patterns, cardinality and per-string
`maxLength` — which the validator counts in UTF-16 code units. Everything else is semantic:

| Left to code | Why the schema cannot see it |
|---|---|
| unique task ids, unique concern/model slots | `uniqueItems` compares whole objects |
| findings tied to an existing, `completed` task | cross-record correlation between two arrays |
| task set identical to the frozen plan, digest match | needs a second document |
| UTF-8 byte budgets (4 KiB body, 2 KiB diagnostic, 8 KiB status) | `maxLength` is not a byte count |
| manifest digests and byte counts matching the files named | needs the files |

`tests/skalary/fixtures/review-run/edge/cases.json` holds both halves. A case marked `semantic` is
structurally **valid** on purpose and names the rule that must reject it, so a schema that starts
rejecting one of them fails the test rather than silently moving the boundary.

## Capability gate

`Build-ReviewReport.ps1` stays `#requires -Version 7.0` so a consumer on an older host loads it and
reports a diagnosis instead of failing to parse (D12). The capability itself is proven by
`scripts/skalary/Test-ReviewSchemaCapability.ps1`, wired into `registry-ci.yml` as
`gate:review-schema-capability` ahead of the repository and unit gates on both matrix legs.

It checks the two halves separately — PowerShell 7.6+ and `Test-Json -SchemaFile` — because they
fail differently, then proves every assertion keyword against the committed schemas themselves. The
keyword inventory is read out of the schema files, so a schema that starts using an unproven keyword
turns the gate red rather than trusting the host. Absence is exit `2` plus one bounded terminal
status object; success is exit `0` plus the same shape.

Two simulation seams (`-SimulateVersion`, `-SimulateMissingSchemaFile`) exist for the suite. Both can
only lower reported capability: the simulated version is applied as a minimum against the real one,
and the switch can only remove a parameter. No invocation can talk a real host into skipping a check.

## Corpus and goldens

`tests/skalary/fixtures/review-run/corpus/` holds the real 44-finding review (`b0c0d3` gate 10.7,
65,481 bytes) as **input** rather than as a second copy of the Markdown: a frozen plan, the envelope
bound to it by digest, a provenance file pinning the archived bytes and digest, and the pre-change
semantic projection golden (grouping key, selected title and bodies, derived action, rank/elevation,
model/concern/reference sets, order).

The reconstruction is verified, not asserted: `ReviewReportCorpus.Tests.ps1` renders the committed
envelope through the unchanged formatter and requires byte equality with the archived file, modulo
the two normalizations recorded in the provenance file (em dashes flattened to hyphens, one extra
trailing newline). Regenerate with
`pwsh -NoProfile -File tests/skalary/fixtures/review-run/New-ReviewCorpusFixture.ps1`; the generator
refuses to write a fixture that no longer renders back, and finishes by invoking
`New-ReviewLayoutGolden.ps1` so the new-layout goldens can never describe a superseded envelope.

`new-layout.expectation.json` is the closed content contract for the two published views, and it is
no longer a promise: `new-layout.summary.golden.md` (5,710 bytes) and `new-layout.full.golden.md`
(81,403 bytes) are committed beside it, with their exact byte counts and SHA-256 digests recorded in
both the expectation and the provenance file.

The goldens are produced from the envelope, not copied from anything. `ReviewLayoutReference.psm1`
is a **test-only** deterministic reference renderer: it derives both views from a
`skalary/review-run@1` envelope using the contract alone — the merge, elevation and ordering rules
`Build-ReviewReport.ps1` already implements, plus D4 attendance and D5/D15 encoding — and performs
no file I/O, no publication and no schema loading. Step 1.2 owns the production renderer,
`Freeze`/`Publish` and the module; it must reproduce these exact bytes, and
`ReviewReportCorpus.Tests.ps1` asserts that nothing in `scripts/skalary/` claims to yet.

Regenerate with `pwsh -NoProfile -File tests/skalary/fixtures/review-run/New-ReviewLayoutGolden.ps1`;
the generator refuses to write a golden that is not stable across `tr-TR`, `cs-CZ`, `de-DE` and the
invariant culture, or that changes when the task and finding arrays are reversed.

### The v1 layout

| View | Bound | Contains |
|---|---|---|
| `summary` | 32 KiB | identity table (run, type, state, plan digest, scope, models, invocations), attendance totals for all six outcomes plus the planned count, and one numbered row per merged finding naming its severity and title |
| `full` | 1 MiB | the same identity table, an untrusted-data warning, one row per planned task (concern, model, outcome, raw-finding count, diagnostic), every merged finding with its severities/concerns/models, distinct bodies, references and the raw records behind it, then the numbered recommendations |

Untrusted-field handling is part of the layout, not a later addition:

- **inline** — scope, model names, titles, actions, references and diagnostics are NFC-normalized,
  whitespace-collapsed, HTML-encoded (`&`, `<`, `>`) and Markdown-escaped, so a title carrying a `|`
  cannot add a table cell and a reference carrying `<script>` cannot become an element;
- **block** — bodies are NFC/LF-normalized, HTML-encoded and wrapped in a backtick fence *longer*
  than any backtick run they contain, so a body cannot close its own fence and continue the
  document;
- **code spans** — only schema-patterned identifiers (run id, task id, concern, outcome, severity,
  digest) are rendered as code, because they are the only values a pattern already confines.

`ReviewReportCorpus.Tests.ps1` renders both views from the corpus under `tr-TR`, `cs-CZ`, `de-DE` and
the invariant culture, and again from an envelope whose properties, tasks and findings are all
reversed, and requires the bytes to equal the committed goldens every time. Completeness is asserted
against the corpus rather than against the goldens — every merged title, every task id, all 60 raw
records, the attendance totals — so a golden that quietly lost a finding fails instead of agreeing
with itself. A hostile envelope covers the encoding rules directly.

`edge/maximum-envelope.spec.json` states the largest legal envelope as a recipe. Step 1.1 owns the
arithmetic only: 128 tasks and 256 findings at every maximum are 2,072,751 bytes, 24,401 under the
2 MiB input cap, and native `Test-Json` accepts them. The 256 findings carry only 128 distinct
`(rootCause, component)` merge keys — seeded per group rather than per finding — because
`maxMergedFindings` is 128: a fixture with 256 keys would describe an envelope the contract does not
admit while calling itself the maximum. Every other field stays at its own maximum, and the group
count is asserted against the vocabulary. Publication runtime and memory are step 1.2.

## Artifact names

`artifactName` carries both a pattern and `maxLength: 96`. The pattern alone caps the *tail* at 94
characters, which would admit a 100-character `.json` name while `x-skalary-limits` advertises 96;
the length keyword is what closes that gap, and `test:ReviewReport.SchemaCapabilityAndSemantics`
pins the two against each other. `edge/cases.json` sits on both sides of the boundary with the
extension counted in the total: `manifest-name-at-maximum-length` (96 characters, accepted) and
`manifest-name-one-above-maximum-length` (97, rejected). Both satisfy the pattern, so only the
length bound can be what separates them.
