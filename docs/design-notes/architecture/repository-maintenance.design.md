---
description: Operator-controlled repository survey, advisory evidence record, dispositions, and existing plan/archive handoffs.
globs:
  - plugins/repository-maintenance/**
  - tests/skalary/RepositoryMaintenance.Tests.ps1
  - docs/repository-maintenance.md
---

# Repository maintenance

`/rcs` performs a repository-wide structural survey and risk-selected traces. It is advisory: source
criteria, architecture contracts, design notes, and current execution gates remain authoritative.
Implementation fixes, deletion, criteria changes, and archival are never inferred from a finding.

## Architecture

| Surface | Owner |
|---|---|
| `repository-maintenance` plugin | `/rcs`, audit and decision guidance, record helper/template, structural evals |
| Existing plan helpers | Plan/epic inventory, state, index, and bounded historical-context reads |
| `docs/repository-maintenance.md` | One fixed, readable evidence and scoped-disposition record |
| `/cip` and architecture maintenance | Corrective implementation planning and contract changes |
| Existing `/ci` and archive paths | Completion gates and separate archive handoff |

The plugin bundles canonical script closures through `Sync-PluginScripts.ps1`; installed payloads do
not import sibling-plugin or source-tree paths. Plan intent, requirements, notes, manifests, standards,
and code retain their existing authority and provenance.

## Key patterns

- Probe the plan corpus before calling `Get-PlanIndex.ps1`; missing corpora, malformed plans, absent
  intent, unread historical sources, and unsupported tracing tools are explicit coverage gaps.
- Use current `PlanState.psm1` inventory and state plus at most three operator-selected historical
  artifacts per request. The current index does not provide enhanced intent/epic-goal snippets.
- Derive subsystem boundaries from current indexes, plugin manifests, entry points, project/build
  files, and layout. Do not add a subsystem registry or reconstruct legacy intent.
- Keep classifications separate: defect/drift, alignment question, unfinished work, optional
  improvement, and coverage gap. Dead-code advice investigates supported public, manual, registered,
  test, generated, dynamic, and external roots; no-reference alone is not proof.
- Preserve findings and decisions in the central Markdown record. Matching uses exact ID, subject,
  scope, and citations. Ambiguous reuse is an operator decision; partial runs never resolve unseen
  findings.
- The writer accepts one fixed path, enforces a 128-KiB UTF-8 limit, screens secrets, rejects malformed
  content and linked/reparse path components, and atomically replaces only the record.
- Accepted drift and won't-fix decisions are scoped, dated, evidence-cited, and revisited when their
  evidence or assumptions change. Corrective plans and archive results are recorded only after the
  selected existing handoff succeeds.
- Standalone plan archival remains an existing `/ci` operator route; there is no standalone archive
  script in this plugin. `Archive-Epic.ps1` remains the epic route.

## Constraints

The audit is not exhaustive, does not assign a quality score, and does not certify unexamined code as
clean. A full documentation/reference sweep, dependency/security audit, network crawl, broad suite,
and premium eval are separate requests. Structural checks protect guidance; they do not measure
semantic audit quality.

## Dubious decisions

One central record duplicates references to owning intent and contracts, but makes cross-run evidence
and operator choices inspectable in one place. It is advisory and must link to the authority it does
not replace. Revisit if bounded intake or conflicting copies prevent reliable use.
