# Collation guide (shared by `/cr` and `/dr`)

Merging 6–28 reviewer outputs into one report is deterministic formatting, so it is a script, not a
prompt. `Build-ReviewReport.ps1` is bundled into this skill's `scripts/` folder and installed with
it. Both installed copies of this guide (`.github/skills/cr/assets/collation-guide.md` and
`.github/skills/dr/assets/collation-guide.md`) are byte-identical by construction — edit one and the
drift gate fails until both match.

## 1. Build typed findings

Every finding a reviewer returns becomes one object:

| Field | Required | Meaning |
|---|---|---|
| `Concern` | yes | the concern id that surfaced it, e.g. `security` |
| `Model` | yes | the model that produced it, in the roster's qualified form |
| `Severity` | yes | `Critical` · `High` · `Medium` · `Low` |
| `Title` | yes | one-line summary |
| `Body` | no | description paragraphs, verbatim from the reviewer |
| `References` | no | string or string[] of file/step references |
| `RootCause` | no | explicit grouping key; falls back to the normalized title |
| `Component` | no | explicit grouping key; falls back to the first reference |
| `Action` | no | one-sentence recommendation; falls back to the body's first sentence |

Set `RootCause` and `Component` whenever two reviewers describe the same defect in different words —
they are the grouping keys, and leaving them empty makes the dedup fall back to title text.

Do not rewrite a reviewer's body while transcribing it, and do not drop a finding because another
reviewer already reported it: collapsing duplicates is the script's job, and the record of *which*
models agreed is what drives severity elevation.

## 2. Run the formatter

```powershell
pwsh -NoProfile -File .github/skills/<skill>/scripts/Build-ReviewReport.ps1 `
  -Finding $findings -Model $roster -Scope '<what was reviewed>' `
  -ReportTitle '<Code Review|Design Review>' `
  -InvocationCount <dispatched> -InvocationBudget 28
```

- `-Model` is the roster **actually dispatched**, including a Pro-tier fallback substitution. The
  script elevates a finding's severity only when *every* listed model flagged it, so an inflated
  roster silently suppresses elevation.
- `-InvocationCount` is the number of reviewer invocations you actually made; the header line
  reports it against the budget.
- `-Scope` is the one-line description of what was reviewed.
- An empty `-Finding` array is valid and returns a well-formed "No findings." report — never
  hand-write that case either.

## 3. Write what it returns

Print the returned text verbatim. The report layout, the merge rule, the dedup rule, the
severity-elevation rule, and the sort order all live in the script; re-deriving any of them in prose
would let two review types drift apart and make the output unreviewable against a fixture.

The only text you add is what surrounds the report: the closing question about which findings to act
on, and any advisory note (for example a reviewer's self-reported model, which is **not** evidence).
