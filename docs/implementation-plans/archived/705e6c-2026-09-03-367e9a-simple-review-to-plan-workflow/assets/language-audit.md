# Active policy-language audit

**Status: closed in Step 5.1.** Unresolved policy absolutes: **0**. Unresolved fuzzy requirements:
**0**. This is a reviewed documentation inventory, not an executable gate.

## Scope and counts

Case-insensitive whole-word rescan at Step 5.1 closure. Counts are lexical inventory, not defect
counts. Scope is the manifest-declared canonical plugin Markdown, `.github/copilot-instructions.md`,
the design-note index plus every indexed design note, and the architecture index plus every indexed
architecture note. Generated `.github` copies, non-indexed architecture archives/staging, the
non-authoritative generated architecture compatibility view, and human operator docs are excluded.

| Active authority | Files scanned | Files with hits | Matching lines | Term occurrences |
|---|---:|---:|---:|---:|
| Manifest-declared canonical plugin Markdown | 44 | 42 | 294 | 358 |
| `.github/copilot-instructions.md` | 1 | 1 | 8 | 11 |
| Active design-note index and indexed notes | 26 | 25 | 297 | 374 |
| Active architecture index and indexed notes | 4 | 4 | 21 | 21 |
| **Total** | **75** | **72** | **620** | **764** |

The scan vocabulary was `always`, `never`, `must`, `shall`, `required`, `only`, `cannot`, `do not`,
`refuse`, `prohibit*`, `detailed`, `thorough`, `robust`, `appropriate`, `comprehensive`, `fast`, and
`secure`. The 11 remaining seeded-fuzzy hits are protocol vocabulary/examples (8), the Git term
`non-fast-forward` (2), and descriptive text introducing the design-note index (1); no active behavioral
requirement relies on a seeded fuzzy word. The architecture archive, staging area, compatibility
view, archived plans/evidence, and operator tutorial are retained documentation, not active policy
authority.

Counts by normalized match: `always` 21; `never` 182; `must` 71; `shall` 1; `required` 36; `only` 321;
`cannot` 43; `do not` 69; `refuse` 7; `prohibit`/`prohibited` 2; `detailed` 2; `thorough` 1; `robust` 2;
`appropriate` 1; `comprehensive` 1; `fast` 3; `secure` 1.

## Closure classification

Every one of the 764 lexical occurrences was reviewed with this mutually exclusive precedence:

1. syntax, identifiers, quotations, examples under analysis, historical text, and already-observable
   descriptions are intentional non-policy exclusions;
2. a fuzzy term used as policy must carry its criterion, threshold, example, or explicit
   interpretation, otherwise it is unresolved;
3. a behavior rule with a stated trigger or exception is a rewritten conditional rule;
4. every remaining behavior-asserting absolute is a retained invariant and belongs to one of the
   reasoned families below.

Closure found no occurrence outside those four classes. The 11 fuzzy-term hits are all intentional
non-policy exclusions: protocol vocabulary/examples (8), Git's `non-fast-forward` term (2), and the
descriptive introduction to the design-note index (1). The previously fuzzy requirements are now
expressed through observable wording recorded below.

## Confirmed unconditional invariants retained

| Category and representative files | Reason it has no operator exception |
|---|---|
| Secret screening and untrusted-data handling — CIP/CEP, CR/DR, SI, `review-reporting.design.md` | Repository/history/review text cannot become executable instruction, and credentials cannot be emitted. This is the accepted content boundary. |
| Destructive and remote mutation guards — autopilot, plugin-manager, process-pr-comments, SI | Force push, unauthorized merge, hidden destructive mutation, and workflow-bearing SI edits cross irreversible or credential-bearing boundaries. |
| Physical path confinement — `arch-install-confinement.md`, plugin-manager, direct review report rules | A payload or report outside its canonical root violates the installer/report boundary; linked or escaping destinations have no safe override. |
| Confirmed-plan criteria protection — CI/autopilot and `arch-direct-workflow.md` | Intent, requirements, risks, and decisions are operator-confirmed execution input. Changes return to CIP rather than weakening execution. |
| Read-only CR/DR and closed verdicts — CR/DR skills and agents | A reviewer cannot edit reviewed material; incomplete attendance cannot produce `clean`. |
| Human-only architecture lock promotion — architecture-notes skill | Autonomous promotion would claim human approval that Git metadata cannot prove. |
| Explicit finite budgets, evidence types, and status/exit values — direct workflow skills/notes | These are closed protocol values needed for deterministic interoperability, not preferences. |
| Canonical-source and generated-copy ownership — customization and registry notes | Editing generated dogfood/catalog copies would create drift; canonical files and sync commands are the sole authority. |

## Conditional rules rewritten or made explicit

| Condition | Behavior | Exception / otherwise | Files |
|---|---|---|---|
| A predefined choice has non-obvious consequences, terminology, relationships, or sequencing | Give both hosts the same context, example, benefits, pros/cons, recommendation/default, effort and complexity scores; diagram relationships/sequencing | Explicit trivial yes/no stays concise; free-form input is one focused question at a time | global instructions; CIP shared protocol; CR, DR, CI, autopilot surfaces; direct-workflow/design notes |
| A behavior-asserting absolute is found in operator requirements or relevant active policy and is not already confirmed unconditional | Show candidate `Condition`, `Behavior`, and `Exception`; ask the operator to confirm or revise | Retain a confirmed unconditional invariant with its reason | CIP shared protocol |
| A seeded fuzzy term states a requirement without observable meaning | Ask for a criterion, threshold, or example before drafting | Ignore code/schema terms, quotations, analyzed examples, format grammar, and already-observable descriptive prose | CIP shared protocol |
| A planning or implementation choice spans design and acceptance criteria | Use one combined Designer/Validator call | Otherwise the orchestrator handles it directly | CIP, CEP, CI |
| Corrective changes alter reviewed scope | Replace the stage report within budget | If scope is unchanged, do not rerun | CR, CI, autopilot |
| Autonomous execution reaches a complex operator decision | Exit `42` with the complete decision brief for host-equivalent resume | Continue directly for explicit trivial choices and confirmed behavior | autopilot skill/agent |

## Clarified fuzzy requirements

| Former wording | Observable interpretation | Files |
|---|---|---|
| “appropriate subfolder” | Choose by primary scope: component boundary, test infrastructure, workflow/agent coordination, user-facing interface, or repo-wide tooling; create another named scope only if none matches | design-notes skill, index template, active design-note index |
| “fast, accurate agent context” | Keep accurate decisions/contracts/constraints/exceptions/minimal examples and duplicate no source text | design-note writing-style template and active note |
| Seeded operator terms | CIP asks what criterion, threshold, example, failures, or retry count demonstrates the requirement before it drafts | CIP shared protocol |

## Intentionally excluded occurrences

- Archived implementation plans/history: historical evidence, not active policy.
- `.github/skills`, `.github/agents`, and `.github/prompts`: generated dogfood, synchronized from plugin
  sources rather than treated as edit authority.
- `docs/operator-guide/**`: human tutorial, explicitly excluded from auto-loading and design-note
  compaction.
- `docs/architecture-notes/archives/**`, `docs/architecture-notes/.staging/**`, and
  `architecture.human.md`: historical, quarantined, or generated non-authority.
- `plugins/**/evals/**/fixtures`: quoted test inputs, including intentionally bad policy.
- External schema/tool keywords, code identifiers, command flags, and format grammar such as PowerShell
  `Mandatory`, JSON Schema `required`, and Git `non-fast-forward`.
- Prompt descriptions, quotations, examples being analyzed, and ordinary descriptive prose when the
  sentence already names an observable fact.

No prose-policy compiler, linter service, schema, or runtime gate was added.
