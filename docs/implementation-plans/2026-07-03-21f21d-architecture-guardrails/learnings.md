## Learnings Capture
Phase: 1

No entries for this phase.

## Learnings Capture
Phase: 2

- [-] [trigger:plan-contradiction] SKILL.md forward-referenced enforcement it cannot deliver alone (lock authorization, human-doc generator, runner). DR flagged as Criticals. Learning: a skill's prose must not claim a gate that a later-phase script provides; mark forward-references explicitly and state what the current gate does NOT do. Fold machine-enforcement gaps back into the owning phase's REQs.

## Learnings Capture
Phase: 3

- [-] [trigger:reusable-pattern] Generated docs with in-place regenerated regions (BEGIN/END marker splice) must HTML-escape angle brackets in any untrusted interpolated text, else the text can emit the region end marker and corrupt the next regen (IndexOf finds injected marker first). Pair with ordinal IndexOf. Same class as harvest glob-frontmatter leak: treat all contract-derived text as inert data at every render boundary (markdown cells, mermaid labels, HTML-comment markers).

## Learnings Capture
Phase: 4

- [-] [trigger:reusable-pattern] Freshness receipts must bind BOTH file content AND the semantic binding (adapter, spec, target set, maturity) via a NUL-prefixed synthetic hash record, so repointing a contract without editing files still invalidates prior receipts. And any pass verdict must be gated on ran=true at all three layers (builder throw, gate mapping, JSON schema conditional) to prevent a locked false-green.
