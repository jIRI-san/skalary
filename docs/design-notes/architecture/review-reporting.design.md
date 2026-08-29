---
description: The review-run v1 data contract, engine, CR/DR caller lifecycle, distribution, consumer fixtures, and structural evidence. Load before changing review schemas/runtime, CR/DR collation or evals, or ReviewReport/ReviewConsumer tests.
globs:
  - schemas/review/**
  - scripts/skalary/Test-ReviewSchemaCapability.ps1
  - scripts/skalary/Build-ReviewReport.ps1
  - scripts/skalary/ReviewRun.psm1
  - scripts/skalary/Get-ReviewRun.ps1
  - scripts/skalary/Remove-ReviewRun.ps1
  - scripts/skalary/Resolve-ReviewStandards.ps1
  - tests/skalary/ReviewStandards.Tests.ps1
  - tests/skalary/fixtures/review-run/**
  - tests/skalary/ReviewCorroboration.Tests.ps1
  - tests/skalary/ReviewReport*.Tests.ps1
  - tests/skalary/ReviewRun*.Tests.ps1
  - tests/skalary/ReviewConsumerInstall.Tests.ps1
  - tests/evals/EvalCommon.psm1
  - plugins/code-review/agents/**
  - plugins/code-review/skills/cr/**
  - plugins/code-review/evals/**
  - plugins/design-review/agents/**
  - plugins/design-review/skills/dr/**
  - plugins/design-review/evals/**
---

# Review reporting

Plan `c21cdc` turns a review run into one versioned data artifact. It owns the schemas and capability
gate, the engine that freezes/publishes/reads a run, the shared CR/DR caller lifecycle, distributed
consumer closure, and the structural/runtime evidence that keeps those installed copies truthful.

## Artifacts and their schemas

| Schema | Artifact | Written by |
|---|---|---|
| `schemas/review/review-plan.schema.json` | the frozen planned-task set, before any reviewer is dispatched | `Freeze` |
| `schemas/review/review-run.schema.json` | the final `skalary/review-run@1` envelope | `Publish` |
| `schemas/review/review-manifest.schema.json` | the publication commit point, replaced last | `Publish` |
| `schemas/review/review-admission.schema.json` | strict terminal-admission state and optional preserved-source descriptor | `Publish`/`Freeze` |
| `schemas/review/terminal-status.schema.json` | the single JSON object every terminal path prints | every mode, including the preflight |
| `schemas/review/review-limits.schema.json` | the shared limit and leaf-type vocabulary | nothing — it is read, never emitted |

`$id` is the repository URL for the file; the envelope discriminator is `skalary/review-run@1`
(D2). Every object is closed, so there is no aggregate property for a caller to supply: counts,
attendance and run state are derived from `tasks`.

## Why the vocabulary is embedded rather than referenced

`review-limits.schema.json` owns every shared definition. The five validation schemas **embed** the
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
| scope digest, canonical path uniqueness, code/design source rules | derived across the frozen descriptor and path records |
| model-selection coverage and fallback/degradation consistency | correlated with the declared roster |
| UTF-8 byte budgets (4 KiB body, 2 KiB diagnostic, 8 KiB status) | `maxLength` is not a byte count |
| the 128 **merged**-finding maximum | the merged count is a function of the renderer's grouping key, not of `maxItems` |
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

Installed CR/DR consumers therefore must provision PowerShell 7.6+ before dispatch. The runtime has
no package or vendored-validator fallback: an incapable host receives the bounded exit-2 diagnosis
and runs zero reviewers. The repository README and both installed collation guides carry this
prerequisite; the wrapper's lower `#requires` is diagnostic compatibility, not runtime support.

Two simulation seams (`-SimulateVersion`, `-SimulateMissingSchemaFile`) exist for the suite. Both can
only lower reported capability: the simulated version is applied as a minimum against the real one,
and the switch can only remove a parameter. No invocation can talk a real host into skipping a check.

## Corpus and goldens

`tests/skalary/fixtures/review-run/corpus/` holds the real 44-finding review (`b0c0d3` gate 10.7,
65,481 bytes) as **input** rather than as a second copy of the Markdown: a frozen plan, the envelope
bound to it by digest, a provenance file pinning the archived bytes and digest, and the pre-change
semantic projection golden (grouping key, selected title and bodies, derived action, rank/elevation,
model/concern/reference sets, order).

The legacy binding is semantic, not a claim that the retired formatter still runs:
`ReviewReportCorpus.Tests.ps1` reconstructs every field of the closed legacy projection from the
committed envelope and compares it with the projection recovered from the independently archived,
digest-pinned report. The archived bytes remain a historical provenance receipt, including the two
recorded normalizations; they are not compared to output from the new renderer. Regenerate with
`pwsh -NoProfile -File tests/skalary/fixtures/review-run/New-ReviewCorpusFixture.ps1`; the generator
rebuilds the envelope and projection from that archived source, and finishes by invoking
`New-ReviewLayoutGolden.ps1` so the new-layout goldens can never describe a superseded envelope.

`new-layout.expectation.json` is the closed content contract for the two published views, and it is
no longer a promise: `new-layout.summary.golden.md` (7,278 bytes) and `new-layout.full.golden.md`
(94,468 bytes) are committed beside it, with their exact byte counts and SHA-256 digests recorded in
both the expectation and the provenance file.

The goldens are produced from the envelope, not copied from anything. `ReviewLayoutReference.psm1`
is a **test-only** deterministic reference renderer: it derives both views from a
`skalary/review-run@1` envelope using the contract alone — merge, corroboration, elevation, ordering,
D4 attendance, and D5/D15 encoding — and performs no file I/O, no publication and no schema loading.
The production renderer, `Freeze`/`Publish`, and the module reproduce these exact bytes, and
`ReviewReportCorpus.Tests.ps1` holds the production and reference renderers equal.

Regenerate with `pwsh -NoProfile -File tests/skalary/fixtures/review-run/New-ReviewLayoutGolden.ps1`;
the generator refuses to write a golden that is not stable across `tr-TR`, `cs-CZ`, `de-DE` and the
invariant culture, or that changes when the task and finding arrays are reversed.

### The v1 layout

| View | Bound | Contains |
|---|---|---|
| `summary` | 32 KiB | identity table (run, type, state, plan/scope digests, structural content trust, requested/declared model state, invocations), attendance totals for all six outcomes plus the planned count, and one numbered row per merged finding naming raw/effective severity, compact support/attendance/similarity/corroboration codes, title, and a lossless reason-legend key |
| `full` | 1 MiB | the same identity table and structural trust marker, one row per planned task (concern, declared model label, outcome, raw-finding count, diagnostic), every merged finding with raw/effective severity, support count, attendance, similarity, corroboration, reason, concerns/declared model labels, distinct bodies, references and raw records, then recommendations |

Untrusted-field handling is part of the layout, not a later addition:

- **inline** — scope, model names, titles, actions, references and diagnostics are NFC-normalized,
  whitespace-collapsed, HTML-encoded (`&`, `<`, `>`) and Markdown-escaped, so a title carrying a `|`
  cannot add a table cell and a reference carrying `<script>` cannot become an element;
- **block** — bodies are NFC/LF-normalized, HTML-encoded and wrapped in a backtick fence *longer*
  than any backtick run they contain, so a body cannot close its own fence and continue the
  document;
- **trust** — `contentTrust: reviewer-authored-data` is schema-required, manifest-bound, and rendered
  as a machine-readable marker/table value. Artifacts contain no AI-directed imperative warning;
  trusted readers/UI choose handling from the structural field;
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
count is asserted against the vocabulary.

The step-1.2 budget worker writes that envelope as **compact** JSON, because the recipe's arithmetic is
compact-JSON arithmetic: an indented copy of the same records is over the 2 MiB input cap and would be
refused by input-byte admission before the render budget the fixture exists to measure. (That is not a
gap in the fixture — it is a real case, and
`test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard` covers it separately with an
indented, schema-valid, over-cap envelope that must be terminal exit `3`.) The structural maximum's 256
findings carry 1 MiB of bodies alone, so its full view is ~1.8 MiB and is correctly rejected as
admission; `test:ReviewReport.MaximumEnvelopeBudget` proves the whole render-and-admit decision stays
inside the platform ceiling (10 seconds on Linux, 30 seconds on Windows) and 256 MiB of sampled
private-byte growth in a child process. The worker records
OS and PowerShell identity with its measured wall-clock/private-byte result, and the named test is
mandatory on both Windows and Linux CI legs—never skipped—so "cross-platform" means the same committed
recipe executes under each supported host rather than extrapolating one local measurement.

## Artifact names

`artifactName` carries both a pattern and `maxLength: 96`. The pattern alone caps the *tail* at 94
characters, which would admit a 100-character `.json` name while `x-skalary-limits` advertises 96;
the length keyword is what closes that gap, and `test:ReviewReport.SchemaCapabilityAndSemantics`
pins the two against each other. `edge/cases.json` sits on both sides of the boundary with the
extension counted in the total: `manifest-name-at-maximum-length` (96 characters, accepted) and
`manifest-name-one-above-maximum-length` (97, rejected). Both satisfy the pattern, so only the
length bound can be what separates them.

The schema bounds the *shape* of a name; the engine narrows it further to a content address
(`<role>.<sha256-hex>.<ext>`, 79–82 characters, comfortably inside the bound) and the reader requires
that narrower form. Keeping the schema at the general pattern is deliberate: it describes what a
manifest may say, while verification — name equals digest equals bytes — is a reader fact, exactly as
the manifest schema's own description states.

## Terminal status and a rejected run id

`terminal-status.schema.json` requires a `runId` on every `freeze`/`publish` status, because a status
that names no run cannot be attributed to one. A caller-supplied run id that is *not* a UUID is the one
exception: it is unbounded text (a 9 KiB argument both breaks the 8 KiB stdout budget and violates the
schema's UUID pattern), so it is never echoed. Those statuses carry `runIdRejected: true` instead, and
the schema binds that to exactly the invalid exit `2` and forbids carrying both fields — a status
cannot both name a run and say its id was rejected. `Get-ReviewTerminalStatusJson` and
`Write-ReviewTerminalStatus` are exported and therefore reachable from callers no CLI path controls, so
they **normalize** rather than trust: a rejected id offered with any other exit or state is emitted as
that one bound combination, and the writer returns the exit code the object states, so stdout and the
process exit can never disagree. Bounded, schema-valid output is preferred over throwing, which would
leave a caller with no terminal object at all. The emitter shrinks a status to fit by dropping
diagnostics from the end and then halving the message, always strictly monotonically and with a
terminating floor, so it can no longer spin on a size it cannot reach.

## The engine (step 1.2)

`scripts/skalary/ReviewRun.psm1` is the whole engine. The three CLIs are thin shells over it:

| Script | Modes | Owns |
|---|---|---|
| `Build-ReviewReport.ps1` | `-Mode Freeze\|Publish -RunId <uuid> [-PlanDir]` | freeze and publish through the fixed installed boundary |
| `Get-ReviewRun.ps1` | `-RunId [-PlanDir] [-View Summary\|Full]`, `-ListIncomplete`, preparation/admission/rollup modes | the only verifying reader; both views verify the complete manifest and selected role bound |
| `Remove-ReviewRun.ps1` | `-RunId [-Force]` | generic-run cleanup |

Keeping the logic in the module is deliberate: the broad failure matrix and the fault seams run
in-process against the module (RISK-14/RISK-5), while a bounded installed-consumer matrix proves the
CLI wiring and exact exits. The retired `b0c0d3` object API is not present.
`Build-ReviewReport.ps1` carries literal `$PSScriptRoot` references
for the engine, reader, and cleanup helper; the engine carries the closed five-file schema reference
set. `Sync-PluginScripts.ps1` follows that closure into both `cr` and `dr`, copies schema sidecars only
from canonical `schemas/review/`, preserves `schemas/review/` below each bundle, recursively prunes
stale managed files, and bumps each affected plugin once per sync. Every generated file remains an
explicit `plugin.json` mapping; no alternate manifest field owns sidecars.

### The production renderer is a verbatim port

The projection and both views are a line-for-line port of the test-only
`ReviewLayoutReference.psm1`. Step 1.1 committed byte goldens the reference renderer produces; the
production renderer must reproduce those exact bytes, so `ReviewReportCorpus.Tests.ps1` renders the
corpus through **both** (the production module is imported there under a `Prod` prefix) and requires
each to equal the committed goldens. The two derivations are held equal by the fixture, never by each
other. Any change to merge, elevation, ordering or encoding must move the goldens and both renderers
together or the corpus test fails.

"Verbatim" covers layout, not defects: the production renderer additionally uses ordinal maps
throughout, preserves colliding raw records, sorts model/title/body records instead of packed strings,
and replaces C0 controls with Control Pictures (see canonicalization below). Those paths are unreachable
for the corpus — it is ASCII, LF, control-free and every model is in the roster — so the goldens are
unaffected, which is exactly why the corpus cannot be the only proof and each case is pinned separately.
Publish computes the merged projection once and renders both views from it; calling either exported
view helper with `-Run` still computes its own projection for compatibility. The shared projection is
required for the maximum-envelope cost bound—doing the same grouping pass once per view wastes most
of the platform budget without changing bytes.

### Lifecycle, state and idempotency

The state machine is `new -> frozen -> published`, with `admission` as a terminal side state, decided
by engine-owned commit markers: a `review-run.manifest.json` means published,
`.review-run.admission.json` means the run reached a terminal byte-budget decision, and
`.review-run.frozen` binds the accepted plan digest. The frozen marker is replaced last under the run
lock, after `review-plan.<sha256>.json`; a generation without its marker is an interrupted Freeze that
only an identical replay may complete. A marker whose generation was removed stays frozen but invalid,
so deleting the content-addressed plan cannot reopen the UUID for a replacement plan.

The caller controls only the two fixed `.input.json` names. Engine-owned fixed files are state
markers: `.review-run.frozen`, `.review-run.admission.json`, the stable lock, and
`review-run.manifest.json` as the final publication commit point. **Every generation file — the
frozen plan included — is content-addressed** as `<role>.<sha256-hex>.<ext>`
(`review-plan.<hex>.json`, `review-run.<hex>.json`, `review-summary.<hex>.md`,
`review-full.<hex>.md`). A name is therefore a claim about bytes that both `Publish` and the reader
verify. A mutable fixed-name frozen plan could be edited in place and still look like a plan; a
content-addressed one cannot be edited without either breaking its own name or creating a second
candidate, and both are detected.

- **Freeze** reads `review-plan.input.json` (the caller renamed it; see the handshake below), enforces
  the input byte budget on the bytes on disk, validates structurally (`Test-Json`) then semantically
  after canonicalization (so NFC/LF cannot collapse uniqueness after validation). For branch mode it
  resolves base/head through Git to full commit SHAs and replaces caller path/status claims with
  `git diff --name-status --no-renames`; other modes retain their canonical records. It scans every
  untrusted plan string for credential shapes before Git or any value-bearing semantic diagnostic, then
  verifies scope, exact model-selection coverage, and every task model inside the frozen roster, and
  writes `review-plan.<digest>.json` and then its independent frozen-state marker **under the run
  lock**. An identical replay is idempotent; a
  *different* plan under a frozen run id is exit `2` — freeze is immutable. Under that same lock it
  decides `published` state **explicitly** rather than inferring "no plan file, therefore new": a
  published run whose plan generation was removed or renamed presents exactly that way, and writing a
  fresh plan into it would leave a run whose committed manifest and whose frozen plan disagree. A
  published run id is verified through the manifest reader — identical plan is an idempotent exit `0`,
  a different plan or a manifest that does not verify is exit `2` — and **no branch writes a
  replacement plan generation**.
- **Publish** requires exactly one frozen plan whose bytes match its own content address (else exit
  `2`), reads `review-result.input.json`, and binds the result to the plan: the `planDigest` must equal
  the digest of the frozen bytes and all scope/model/trust/task authority must be *exactly* the frozen
  one (RISK-2). It canonicalizes first and reruns structural and semantic validation, then
  canonicalizes, renders both views, checks the byte budgets, takes the lock and — under it — decides
  admission, idempotency and changed reuse before replacing the manifest last. A published run id is
  answered from a manifest verified in full by the same reader a consumer uses (schema, confined
  content-addressed names, byte counts, every digest, run-directory identity and the canonical
  plan/run binding), never by parsing the file inline and trusting `runDigest` alone: identical
  replay is idempotent only over an authority that verifies, a changed result under a published run
  id is exit `2`, and a manifest that fails verification is exit `2` with nothing overwritten.

Run state derives from the task set alone (D4): only an all-`completed` run is `clean` (exit `0`);
every other structurally valid mix is `degraded` (exit `5`, returned only after the artifacts exist).

Every module and CLI path is bounded to `0/2/3/4/5` with exactly one terminal-status object. What used
to escape as an unhandled error — a malformed or tampered frozen plan, an unreadable published
manifest, a run directory that cannot be created — is now a named exit: `2` for state the engine
refuses to trust or overwrite, `4` for an unexpected failure. `Build-ReviewReport.ps1` wraps the whole
persistence path in a last-resort guard that turns anything still escaping (a broken install, for
instance) into an explicit exit `4` status; it is a reporter, not a fallback, and never retries or
suppresses.

### Schema capability is checked in-module (D12)

The wrapper stays `#requires -Version 7.0`, so the engine cannot assume `Test-Json -SchemaFile` exists.
`Test-ReviewHostSchemaCapability` checks the two halves (PowerShell 7.6+, and the parameter itself) and
`Freeze`/`Publish` return a bounded exit `2` naming what is missing rather than throwing a parameter
error. `Set-ReviewSchemaCapabilitySimulation` is a test-only seam with the same semantics as
`Test-ReviewSchemaCapability.ps1`'s: the simulated version applies as a *minimum* against the real one
and the switch can only remove a capability, so no invocation can talk a real host into skipping a check.

### Canonicalization (D15)

`ConvertTo-ReviewCanonicalJson` puts an envelope in the one form two equivalent documents must share:

- **Every string is NFC and LF.** The two representational differences a JSON string can carry without
  being a different document — the composition of a grapheme (`Café` versus `Cafe` + U+0301) and the
  line ending (`\r\n`/`\r` versus `\n`) — are removed, so a CRLF-authored envelope and its LF twin have
  one digest, one content address and one publication rather than two conflicting ones. An unpaired
  surrogate is replaced with U+FFFD *before* the digest is taken, because the UTF-8 encoder would
  substitute it anyway and the canonical text and the canonical bytes must agree.
- **Every schema-valid integral number is written as an integer.** Draft 2020-12 accepts `1.0` wherever
  it accepts `1`, and `ConvertFrom-Json` returns a double, so `"invocationBudget": 1.0` used to
  serialize back as `1.0` and hash differently from the identical document spelled `1`. A genuinely
  fractional value, and anything outside the exact `2^53` round trip, is left untouched.
- **Object keys and frozen-field comparisons are ordinal** — never `Sort-Object` or PowerShell's
  case-insensitive equality. Scope, roster and task model case are part of the frozen contract. Object
  keys and set-valued arrays (`roster`, `tasks` by id, `findings` by an ordinal field tuple, each
  finding's `references`) use ordinal ordering so culture cannot change canonical bytes. Ordinal is
  also why the key map is an `OrderedDictionary` with
  `StringComparer.Ordinal` rather than `[ordered]@{}`: PowerShell's ordered dictionary compares keys
  case-insensitively, which would silently merge two case-distinct members of a "lossless" document.
  The same rule holds inside the projection (task map, merge map, sort map): a case-insensitive
  hashtable is how a merged group disappears.
- **Output is compact JSON, one trailing `\n`, UTF-8 without BOM.**

Apart from the NFC/LF normalization (and the surrogate substitution above), canonicalization is
lossless: control characters, whitespace and case inside reviewer text survive into the canonical
authority exactly as they arrived. Canonicalization is idempotent — re-canonicalizing a canonical
document returns the same bytes — which is what makes an equivalent replay an *idempotent* replay
rather than a second generation.

The digest is taken **after** canonicalization, so it is stable across raw property order, task/finding
order and culture — proven by rendering the same envelope under `cs-CZ`, `tr-TR`, `de-DE` and the
invariant culture and requiring identical bytes and digests. This reproduces the committed corpus plan
bytes exactly, which is how the corpus `planDigest` binding holds; the corpus is ASCII with LF and
integer numbers, so the added normalizations are a no-op on it and its committed digests are unchanged.

Reduction is a *render-time* property, never a lossy one: two structurally distinct findings can
normalize to the same merge tuple (a title differing only in surrounding whitespace, an explicit
`rootCause` equal to another finding's defaulted one), and every one of them survives into the
projection and the full view in a deterministic ordinal order. Keying a dictionary by that tuple — the
earlier implementation — turned legal input into a crashed publication.

### Observable finding similarity

Corroboration similarity is derived only inside an existing `(rootCause, component)` merge group and
only between findings attributed to distinct declared model labels. It is evidence that two nominally
independent outputs may not be independent; it never proves which model served a request, and absence
of a match means only that no suspicious similarity was observed.

One engine-owned helper canonicalizes each raw finding's title, body, and action independently to NFC,
LF, invariant lowercase Unicode letter/decimal-number words. The three normalized fields remain a
length-prefixed tuple, so reviewer text cannot forge field boundaries. Exact tuple matches always flag.
Otherwise, a pair is a clearly near duplicate only when both combined normalized records have at least
8 distinct tokens and 48 characters and their token-set Jaccard similarity is at least `0.90`. The
fixed content guard prevents short shared boilerplate from suppressing valid corroboration. Comparison
uses the projection's deterministic raw-record order, preserves every raw field unchanged, and records
only `none`, `near-duplicate`, or `exact` on the derived merged entry. Each raw record is normalized
once; exact tuples are indexed by declared model label before lexical comparison, and each near-match
token maps to nested declared-model posting buckets before intersection counts are accumulated.
Same-label buckets therefore never enter work that can only affect cross-label corroboration, and the
pass stops at its first qualifying pair because group-level suspicion is already established.

The merged entry then derives one support state with fixed precedence: any exact or near-duplicate
cross-label pair is `suspicious`; otherwise incomplete task attendance is `degraded`; otherwise two or
more distinct declared model labels are `corroborated`; the remainder is `single-source`. The entry
keeps raw and effective severity separately. A one-rank elevation is allowed only when support is
corroborated, attendance is complete, every declared model label reported the merge group, no
suspicious similarity was observed, and raw severity is below Critical. Suspicious and degraded
support never elevate. Suspicious support sets `NeedsReview`, carries a `needs-review` reason, and makes
an `approved` retained-result verdict invalid even when its effective severity is otherwise
non-blocking.

Each projected finding exposes the engine-owned fields `SupportCount`, `AttendanceState`,
`Similarity`, `CorroborationState`, `RawSeverity`, `EffectiveSeverity`, and `Reason`; none is accepted
from the review-run envelope. The summary renders all seven beside each merged title. The full view
renders the same values in each finding's detail table, keeps every raw record and its original
severity, and labels recommendations with effective severity.

Plan finalization retains the gate-relevant part of that truth without replacing the bounded v1
lifecycle. The compact report records raw/effective severity distributions, corroboration and
similarity distributions, needs-review count, and the complete support/attendance/similarity/reason
tuple for each displayed blocking or non-blocking needs-review finding. The digest-bound receipt
carries the same aggregate distributions. The 8 KiB retained-report bound, manifest-last publication,
verified replay, cleanup tombstone, and exact retained-pair repair rules are unchanged. The committed
corpus reference renderer and byte goldens include these fields so production and fixture rendering
remain independently derived.

`tests/skalary/fixtures/review-run/corroboration-matrix.json` is the compact behavioral corpus for the
derived fields. It fixes exact and near duplicates, unrelated short boilerplate, single-source and
degraded attendance, malicious echo, input-order stability, and unchanged clean elevation. The
`test:ReviewReport.CorroborationMatrix` host verifies every expected projection and raw-record count,
then adds each forbidden derived field to an otherwise schema-valid raw finding and requires the
closed review-run v1 schema to reject it. Derived corroboration and effective severity therefore stay
engine-owned rather than becoming caller assertions.

`ReviewRun.psm1` remains the single canonical implementation of this derivation. The existing plugin
script writer copies it into both CR and DR bundles, bumps each changed plugin version, and the
dogfood, marketplace, and registry writers propagate those exact bytes and hashes. Installed-consumer
tests execute both shipped copies with canonical source fallbacks poisoned; structural CR/DR evals
continue to prove orchestration ownership independently of the report behavior corpus.

### Untrusted text never becomes a delimiter

Every leaf string in the contract is `type: string` with a length bound: a model name, a title or a
body may legally contain `U+0001`. Anywhere such a value was packed into a delimited key, the delimiter
was forgeable, so those keys are now either structured or length-prefixed:

- **Model attribution and unanimity.** The models of a merged group are ordered by sorting *records*
  and carrying the original value through; the sort key is derived and discarded. Packing
  `<roster index>·<model>` and reading the value back from the last delimiter truncated a model
  containing `U+0001` to whatever followed it, which named a model nobody dispatched and — because the
  truncated name no longer matched the roster — silently stopped unanimous agreement from elevating.
  Titles and bodies are ordered the same way.
- **Roster equality and concern/model slots.** Both compare `Get-ReviewOrdinalTupleKey` length-prefixed
  tuples. Joining a roster with `U+0001` made `["a\u0001b"]` compare equal to `["a", "b"]`, so a result
  could claim an attendance set the frozen plan never declared.
- **The merge key and the merged-entry sort key stay delimited, and nothing forgeable is packed into
  them.** Both halves of a merge key come from `Get-ReviewNormalizedKey`, whose output is `[a-z0-9 ]*`;
  the sort key's numeric fields are fixed width, its title is control-safe (see below), and its
  trailing merge key contributes exactly one delimiter, so the composite decomposes uniquely.

**Rendered views never emit a raw C0 control.** `ConvertTo-ReviewInlineText` and
`ConvertTo-ReviewFencedBlock` replace the C0 range and DEL with their Unicode Control Pictures
(U+2400 + code point; DEL → U+2421), keeping block line breaks and tabs. The substitution is
deterministic and injective, so attribution stays complete and readable instead of carrying an
invisible byte a human and a parser read differently. Canonical JSON is untouched by it — this runs in
the render path only, which is exactly the split the contract draws between lossless authority and
bounded views.

### The merged maximum is a semantic rule

`maxMergedFindings` (128) bounds the *merged* set, which no single-document keyword can count: 256 raw
findings are structurally legal and may collapse into anything between one group and 256.
`Test-ReviewRunSemantic` counts distinct `Get-ReviewMergeKey` values — the renderer's own key,
fallbacks included, shared by one function so the two cannot drift — and a run that would render more
groups than the contract admits is exit `2` **before** anything is canonicalized, rendered or written.
It is invalid input, not a byte-budget admission: the input is malformed against the contract rather
than too big for it, and no marker makes the UUID terminal.

**One function is not enough on its own: the key must also be order-invariant.** Validation runs on the
raw document while the renderer runs on the canonical one, and canonicalization sorts `references`
ordinally on canonical text. Taking the component fallback from `references[0]` of each therefore gave
the two callers a different component for the same finding, so the count and the render disagreed in
both directions: raw arrays all leading with one shared reference counted 65 groups, passed the
maximum, and then rendered 130; arrays differing only in order counted 129 where the renderer merges
128, falsely rejecting a legal run. `Get-ReviewMergeKey` therefore applies the *same* canonical text
and the *same* ordinal sort before it picks the first non-blank reference, so the key is a function of
the document rather than of the array order the caller happened to write, and the approved grouping
behavior — component falls back to the canonical first reference — holds identically in both callers.

### Publication safety

- **Manifest last, under a stable lock.** Generation files are written first; the manifest — the sole
  commit point a reader trusts — is replaced last while an exclusive lock on `.review-run.lock` is
  held. The lock file is created once and **never unlinked**: deleting it on release is what breaks
  mutual exclusion, because a process that opens the path after the delete holds a different inode than
  one that opened it before, and both would believe they hold the lock. `Freeze` takes the same lock —
  it decides immutable state — and every state decision (admission, idempotent replay, changed reuse,
  the frozen-plan re-verification) happens *inside* it, so two concurrent calls cannot both pass their
  checks and then both commit. The timeout is the vocabulary's `lockTimeoutSeconds` (5); a test may
  lower it through a module-scoped override, and the CLI never lowers it. A lock it cannot acquire is
  exit `4`.
- **Fault seams (RISK-5).** `Set-ReviewRunFaultSeam` arms a named edge — `during-lock`,
  `after-canonical`, `after-summary`, `after-full`, `before-manifest-swap` — that throws. The CLI never
  arms one, so there is no production failpoint. A fault removes **only the generation files this
  attempt itself wrote**, and only while no committed manifest names them; a directory-wide sweep of
  `*.tmp-*` (the earlier behavior, and after the lock was released at that) would delete a concurrent
  process's staging. Atomic writes clean up their own temporary file and nothing else.
- **Byte admission is terminal, and comes first (D6/D21).** The 2 MiB envelope budget is enforced on
  the bytes actually on disk *before* anything parses them — an oversized envelope must never be
  materialized just to be refused — and again on the canonical bytes. Over budget is exit `3`, never a
  retryable `4`. The same applies to a rendered view over its budget: exit `3` before the manifest
  changes, never truncated, never dropping a finding. A pre-parse/invalid admission is non-restartable.
  A render admission preserves the validated canonical result as a content-addressed source and writes
  a strict `.review-run.admission.json` marker binding its digest, finding count, plan/scope digests,
  and hard limits (`maxRestarts: 1`, `maxPartitions: 16`), so admission outlives the process that decided it: a
  later `Publish` on that UUID is exit `3` again and cannot publish a quietly reduced set, a later
  `Freeze` cannot reopen it, and `Find-IncompleteReviewRun` does not report it as an interrupted run
  to finalize. Child plans carry parent run/digest plus ordered partition index/count. The final reader
  rollup accepts only published children whose path/status records exactly cover the parent scope,
  whose canonical raw-finding multiset exactly equals the preserved source, and whose task/outcome
  records exactly equal the parent source in every child; gaps, duplicates, or outcome changes fail.

  The marker is a state transition like any other, so it is decided *atomically with state* under the
  same lock: `Freeze` may admit only a `new` run and `Publish` only a `frozen` one. An
  already-`admission` run repeats its terminal answer and rewrites nothing; any other state — a
  `published` run above all — is exit `2` with **no marker written**, because an oversized or
  over-budget retry must not be able to stamp `admission` onto committed authority and make a
  verified publication unreadable; and a lock or marker write that fails is an explicit exit `4`
  `failed`, never an exit `3` claiming a terminal decision no later invocation could see. The
  rejected input is already destroyed by then, which the diagnostics of those paths say plainly.
- **Error precedence.** Input-byte admission (a gate that must precede parsing) → parse/schema →
  secret → semantic → render admission → publication. Secret rejection emits only type/location.

### The verifying reader and cleanup

`Get-ReviewRun.ps1` verifies manifests, admission markers/sources, preparation roots, and final
admission rollups. For a published run it reads only the manifest: it schema-validates it, confines every name to a single
path segment, requires each name to be the content address of the bytes it names, verifies each file's
byte count and SHA-256, checks `runDigest`/`planDigest` against the canonical and plan files, requires
`runId` to be the run directory's own id (compared ordinally), and requires the canonical envelope's
`runId` and `planDigest` to agree with the manifest — so a manifest copied from another run cannot read
as this one. Only then does it write the summary to stdout as raw LF-terminated UTF-8, separate from the
8 KiB terminal-status object the publisher prints.

Two of those checks are the reader's *own*, not the manifest's:

- **Per-role byte budgets.** The manifest's `byteCount` is bounded only by the generic 2 MiB envelope
  maximum, so a 900 KiB summary is a structurally valid — and, if the file really carries those bytes,
  digest-consistent — manifest entry. The reader re-derives each role's budget from the schema-owned
  vocabulary (`plan`/`canonical` ≤ `maxEnvelopeBytes`, `summary` ≤ `maxSummaryBytes`, `full` ≤
  `maxFullBytes`) instead of trusting the generic maximum beside the file.
- **Artifact encoding.** Every artifact this engine writes is UTF-8 without a BOM, LF-only and NFC, so
  one that is not is not an artifact this engine produced, whatever its digest agrees with. The NFC
  comparison is ordinal on purpose: PowerShell's own comparison operators are culture-sensitive, and a
  culture-sensitive comparison treats a decomposed string as equal to its composed form — precisely the
  difference being checked.

**Confinement applies to reads exactly as it does to writes.** `Assert-ReviewPathSafe` re-checks the run
directory and every concrete file the manifest names immediately before opening it, so a run directory
or a single leaf artifact swapped for a symlink is refused rather than read from outside the store.
`Read-ReviewManifest` and `Get-ReviewRunSummaryText` take an optional `Boundary`: `Publish`, cleanup and
the CLIs pass the repository root they already resolved, and a direct call with none derives one from
the run directory itself, which can only make the walk longer and therefore stricter. Same-user TOCTOU
inside the remaining window stays a documented residual risk.

Each verified artifact is opened once. `Read-ReviewManifest` retains the verified bytes and parsed
plan/canonical documents in its result; view delivery and finalization consume those values rather than
reopening paths after verification. The public `Files` path map remains for compatibility, but no
authority decision is made from a second read.

`-ListIncomplete` reports frozen-but-unpublished runs through the *same* store resolver Freeze/Publish
use, so a listing is not a second, weaker way to point the engine at a directory, and it validates the
store root and each candidate run directory before enumerating or deciding state.
`Remove-ReviewRun.ps1` removes a generic run, confined to `.github/.skalary/review-runs/`, only from
authority returned by that reader. The cleanup operation itself emits and flushes the verified full
bytes before deletion, so a caller cannot claim delivery with an unchecked digest; direct published
cleanup without verified authority is refused, and `-Force` is limited to unpublished abandoned runs.
For a plan run, `-PlanDir` plus explicit
`-Verdict approved|blocked` verifies the bundle, emits compact sibling files, then removes the live
directory. `<uuid>.review.md` is human evidence bounded by `maxRetainedReportBytes` (8 KiB): identity,
source scope, gate verdict, attendance, raw/effective severity totals, corroboration/similarity totals,
and byte-budgeted blocking and non-blocking needs-review rows with explicit omission counts. The closed
`<uuid>.receipt.json` binds that report's bytes/digest to plan, run, manifest, scope, attendance,
raw/effective severity, corroboration, similarity, and needs-review counts. Approval is impossible
when the run is degraded, has Critical/High effective findings, or has any needs-review finding.
Live `<uuid>/` directories are gitignored; only those compact siblings are committed. Finalization is
serialized by a stable ignored store-level lock and the run publication lock, and supports PowerShell
`ShouldProcess`/`-WhatIf`; dry runs report `would finalize` and write nothing. The live directory is
removed only after both compact files are durable. A cleanup failure returns durable evidence with
`CleanupPending = true`, and the CLI exits `4` rather than reporting complete success. Every retry with
live authority reconstructs the complete expected report and receipt and compares exact bytes; a
partial or tampered pair is repaired before cleanup, including interruption between retained writes.
Cleanup first atomically renames live authority to `.cleanup/<uuid>` (the UUID leaf keeps normal
manifest identity verification valid). Before the rename it atomically writes a stable cleanup marker
binding run id, verdict, and both retained-file digests. It then recursively removes the tombstone with
terminating errors. A partial recursive failure therefore cannot be rediscovered as an incomplete
review and can converge from the marker plus retained pair even if the tombstone manifest was already
deleted. Replay validates and preserves an intact marker-bound pair before invoking the current
renderer, so a renderer upgrade cannot strand cleanup. A missing or tampered pair is regenerated only
when verified cleanup authority reproduces the marker-bound bytes; renderer drift therefore never
silently rewrites retained evidence. Marker identity is checked before repair, so a different verdict
cannot rewrite evidence.
Cleanup diagnostics cross the CLI boundary with exit `4`. Retrying the same verdict verifies the pair and converges cleanup. Historical
live bundles were compacted during migration, so production finalization now accepts only the current
manifest shape and refuses old live authority. Existing compact legacy receipts remain historical
evidence and require no production legacy verifier. Reader and cleanup exits remain `0`, `2`, or `4`.

Wrapped plan review cycles are also immutable historical evidence. `ReviewCycleGate Reopen` is an
operator-authorized append-only remediation, not a rewrite: it records the authorization id and reason
after Wrap and permits a subsequent cycle. Recording that cycle as clean requires the retained
review-run UUID. Evidence receipt construction and PlanCrosscheck both reverify the retained pair,
`code`/`clean`/`approved` state, zero findings and non-completed attendance, the durable clean-cycle
binding, and the reviewed commit. A wrapped/degraded result or a hand-written passed line cannot satisfy
`review:cr`. Plan-finalization accepts only Git-derived whole-branch scope from the canonical
`origin/HEAD` merge base and matching changed-path count; a selected-path, narrowed-base, or uncommitted
review cannot be promoted into whole-plan evidence by copying the current head value. Historical clean
cycle lines without a review-run UUID remain non-qualifying and can only advance through authorized Reopen.

### Locations and the handshake (D14/D16)

A plan run resolves through the `ReviewRuns` kind of `Resolve-PlanAssetPath`
(`<plan>/assets/reviews/<uuid>/`); a generic run resolves under the gitignored
`.github/.skalary/review-runs/<uuid>/`. The caller chooses only a run id and, for a plan run, a plan
directory — repo, schema and output roots are computed from the installed script location. Before any
caller `New-Item` or `edit`, `Get-ReviewRun.ps1 -Prepare` checks the plan directory, `plan.md`, assets
layout anchors, store and run leaf for reparses, then returns the sole run root without writing it.
Freeze refuses to create a missing root.

A plan directory is confined **before** inventory/layout reads, then validated through the plan inventory, not by path shape: it must live under
`docs/implementation-plans/`, carry a `plan.md`, appear in `Get-PlanInventory`, and its inventory id
must resolve back to the same folder through `Resolve-Plan`. Immediately before any write, removal or
verified read, `Assert-ReviewPathSafe` walks from the target up to the repository root and refuses if
any existing component is a symlink or reparse point (RISK-6); same-user TOCTOU inside the remaining
window stays a documented residual risk.

The handshake belongs to the **caller** (D16): it writes `.review-plan.input.tmp` /
`.review-result.input.tmp` and atomically renames it onto `review-plan.input.json` /
`review-result.input.json`. The engine consumes only those two fixed names — it performs no rename — so
a `.tmp` still being written, or abandoned half-written by a crashed caller, is not an input at all and
is neither read nor removed. Input is destroyed after use: removed on success, and overwritten before
unlinking whenever it was rejected.

**The input leaf is confined too, not just its ancestors.** Those two fixed names are the one path
inside a run directory whose content an untrusted caller supplies, and the engine both parses that leaf
and destroys it *in place* — `Remove-ReviewInputSecurely` overwrites the bytes before unlinking. The
ancestor walk never saw a swapped leaf, because every ancestor was still a real directory this engine
created, so a symlink renamed onto the fixed name turned the handshake into an arbitrary-file read and,
worse, an arbitrary-file shredder outside the store. `Assert-ReviewInputLeafSafe` therefore runs before
the leaf is accepted (`Get-ReviewInputPath`), read (`Read-ReviewInputText`) and destroyed
(`Remove-ReviewInputSecurely`, including the pre-scan `Remove-ReviewPendingInput`): it reads the leaf's
attributes with `-Force`, which stats the link rather than its target, refuses a reparse point outright,
and then walks the concrete path to the repository boundary. Every one of those helpers takes the
`Boundary` its mode already resolved. The link is never followed — the target is neither opened, nor
overwritten, nor unlinked — and the refusal surfaces as the contract's bounded exit `4`; the link
itself is simply left where it is.

**Every terminal exit destroys the input, including the ones decided before the secret scan runs.** The
scan needs a frozen plan to bind the result to, so three `Publish` exits are decided before it: an
already-`admission` run, an existing run directory with no frozen plan, and a frozen plan that does not
verify. Each used to return leaving staged reviewer text — which nothing had scanned — on disk. A
retryable exit `4` is the deliberate exception and keeps the input, because the caller is expected to
run the same input again.

### The secret guard (D18/RISK-16)

Before any lossless artifact is written — including the *frozen plan*, which is a committed artifact
one mode before `Publish` ever runs — `Find-ReviewSecret` scans every untrusted field for a
high-confidence credential shape (GitHub PAT/OAuth/fine-grained, AWS access key, Google API key, Slack,
Stripe, npm, PEM private-key banner). For a plan that is `scope`, the roster and every task model; for
a result it is additionally each task diagnostic and every finding string and reference. A hit is exit
`2`: the input is irreversibly destroyed at once (`Remove-ReviewInputSecurely` overwrites then unlinks)
and only the redacted *type* and *location* are reported — never the value.

The allow list is exact, not fuzzy. Only the published AWS documentation key verbatim, or a recognized
provider prefix whose **entire** body is a mask run (`XXXX…`, `****…`) or an exact repetition of a
synthetic marker (`REDACTEDREDACTED…`), is allowed. A substring match — the earlier rule — waved
through any live credential whose body happened to contain `example` or `redacted`, which is precisely
the value the guard exists to stop. The patterns are character classes, never literal tokens. The
behavior is pinned by `tests/skalary/fixtures/review-run/secrets/allow-block-corpus.json`, a
**versioned** corpus that stores only inert fragments and a reconstruction recipe; the test assembles
each token-shaped string at runtime, so no complete provider-token signature is ever committed and
repository push protection cannot trip on the fixture.

### Test inventory (step 1.2)

Focused suites, one evidence id each, all in-process except the budget child:
`test:ReviewReport.FrozenPlanAndAttendanceMatrix`,
`test:ReviewReport.GoldenSemanticParityAndCanonicalization` (extended for the production renderer),
`test:ReviewReport.OutputAdmissionCompletenessReductionAndSecretGuard`,
`test:ReviewReport.ManifestReaderPublicationAndExitMatrix`,
`test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection`,
`test:ReviewReport.EncodingExitDiagnosticAndLockContract`,
`test:ReviewReport.MaximumEnvelopeBudget`. The historical `b0c0d3` semantic expectations remain in
the corpus projection, while the object API and its direct tests were retired in the atomic phase 2
caller migration (REQ-13).

## Concern reviewer authorship

The seven CR and seven DR concern reviewers are build-time generated payloads. Their policy source is
`tools/review-concerns.json`; their read-only stance, no-model declaration, injection guard, context
order, and output structure come from `tools/review-concern-agent.template.md`.
`Sync-ReviewConcerns.ps1` renders the surface-specific agents and both concern-to-ledger maps. See
[review-concern-authoring.design.md](./review-concern-authoring.design.md) for authoring and drift rules.

This generation boundary does not enter review-run v1. Concern agents still return findings only; they
do not freeze, publish, read, retain, or clean run artifacts. The CR/DR orchestrators remain the sole
callers of the review engine and the sole explicit model-binding authority.

The same generator emits each review skill's bounded generic `review-standards.json`. Before Freeze,
the orchestrator invokes its installed `Resolve-ReviewStandards.ps1` once and passes each concern only
its resolved criteria. The fixed optional `docs/review-standards.md` consumer file may extend or replace
only entries marked localizable. It remains repo-owned and absent by default. Resolved criteria are
dispatch-only data: they never enter the review-plan/result handshake, publication manifest, or retained
review-run v1 evidence.

## CR/DR caller adoption (step 2.2)

The legacy `-Finding`/`-Model` parameter set and its generated `[pscustomobject]` examples are gone.
CR and DR share one lifecycle asset: finalize frozen orphans as cancelled, Freeze the complete task
matrix before dispatch, dispatch independently with no prior-result priming or suppression, retain
results in memory, Publish once, then read through the digest-verifying reader. Plan runs preserve
their manifest and generations; generic runs use the cleanup helper only after summary delivery.

The lifecycle remains shared while model policy differs by review type. DR dispatches its two-model
roster on every round; iterative DR callers stop after three rounds by default. CR reads its role
bindings from `skills/cr/assets/model-preferences.md`: post-phase runs freeze primary-only tasks,
while standalone and plan-finalization runs freeze primary + secondary tasks. The backup replaces an
unavailable selected role and never creates an extra task.

The orchestrator agents add `edit`, but their absolute rule permits only
`.review-plan.input.tmp` and `.review-result.input.tmp` under their computed UUID root. Fixed inputs
appear only through the local atomic rename. Terminal text contains paths/UUIDs, never reviewer data.
Every concern reviewer redacts suspected credential values before return, and the engine remains the
independent fail-closed secret guard for both generic and plan-associated inputs.

Terminal handling is complete: `0` clean; `5` published degraded and propagated after delivery; `2`
invalid; `3` terminal for the UUID and either non-restartable or followed by the single bounded
partition generation plus verified rollup; `4` retryable only with identical input after the publication fault is corrected. The two
writer approvals are anchored full-command regex keys with object values
`{"approve":true,"matchCommandLine":true}`; no prefix approval can authorize extra writer flags or a
chained command.

## Consumer truth gates (step 3.1)

CR and DR each own nine stable Tier-1 IDs under `eval:ReviewReport.<CR|DR>.*`. Each concern is a
separate Pester case so writer-scope, ordering, independence, complete/nonzero dispatch, renderer
ownership, fixed roots/policy, degraded-artifact delivery, and bounded-retry regressions identify the
broken contract directly instead of disappearing inside one aggregate eval. Their assertion bodies
are shared through `tests/evals/EvalCommon.psm1`; the thin plugin-local `It` shells preserve separate
CR/DR IDs and plugin attribution without allowing the two contracts to drift. The ordinary
`test:ReviewReport.StructuralEvalDiscovery` gate AST-discovers the exact two ID sets; zero or renamed
cases fail.

`ReviewConsumerInstall.Tests.ps1` copies each plugin's shipped script/schema closure into an isolated
repository and poisons the canonical repository fallback paths. One fixture per plugin executes clean
with findings, completed-with-zero-findings, zero-task rejection, mixed degraded and all-failure plan
runs, orphan cancellation, frozen-plan mutation, secret rejection, reader tamper, fault retry, lock
retry, and generic/plan cleanup behavior. This makes installed CR and DR copies prove the same exits
and persistence contract without silently loading root scripts or schemas.

`test:ReviewReport.TestAndEvalDiscovery` maps every ordinary `test:` marker in this plan to a
discoverable test source and also pins the exact structural eval sets.
`test:ReviewReport.NoNewRuntimeDependency` keeps the engine native: both plugin dependency arrays stay
empty, no root package lock is introduced, and neither plugin gains a vendored validator.

These evidence layers are distinct. Ordinary `test:ReviewReport.*` cases run in `npm test`; the
`eval:ReviewReport.*` cases run in the repository's deliberately separate Tier-1 `npm run eval` gate
and are rerun at the phase crosscheck. Exact-ID discovery proves presence, not execution. A preserved
plan-associated `review:cr` artifact proves the observed frozen roster and outcomes of a live run; it
does not prove served-model identity or replace either deterministic layer.
