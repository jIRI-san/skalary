# Repository maintenance

This is an advisory record. Current source and current gates remain authoritative.

## Source and scope

<!-- rcs:source:start -->
Source commit: b358bb411b846f9691e34333ad7b88a9cbf6945b
Dirty worktree paths: none
<!-- rcs:source:end -->

## Survey

<!-- rcs:survey:start -->
Repository snapshot b358bb411b846f9691e34333ad7b88a9cbf6945b; worktree clean. Top-level boundaries include 15 source plugins, shared PowerShell runtime under scripts/skalary, generated registry and marketplace plus .github dogfood payloads, design/architecture notes, implementation plans and epics, and focused PowerShell/Pester tests. The plan index reports 45 plans (2 active, 43 archived), 496 requirements, 367 risks, 745 decisions, and 0 malformed/unindexed errors; 3 epics (1 active, 2 archived). Active plan 4e0f9b is confirmed, 3/4 steps complete, with host walkthrough/finalization step 2.2 pending. Active plan 961e7d has all 9 checklist steps complete, but no final review or learning artifact was present; no finalization or archive readiness is inferred. Relevant source expectations read: repository-maintenance, simplicity-first, plan-workflow, factory-loop, workshop, plugin-registry, autopilot-execution, architecture index, and active workshop/factory-loop plan intents. Coding style checked in .editorconfig and PSScriptAnalyzerSettings.psd1. No cross-codebase redesign proposal is supported by this bounded evidence; the observed generated script copies and dogfood surfaces follow the documented canonical source/sync model.
<!-- rcs:survey:end -->

## Coverage

<!-- rcs:coverage:start -->
Traced the epic archival path end to end through Archive-Epic, New-Epic child-table refresh, epic inventory parsing, plan-workflow guidance, and archive tests; traced factory-loop production approval, artifact-bound deployment identity, evidence publication, secret screening, and fault-recovery tests. Factory-loop source checks require approval for the exact artifact digest, block declined or unknown decisions, verify production deployment/version identity, and block evidence publication unless deployment-trigger exclusion is acknowledged; focused fixtures cover these invariants. Live provider integrations and live host walkthroughs were not exercised; factory-loop adapters are explicitly project-owned/simulated. Skipped deep traces of the other 14 plugins, full documentation/reference sweep, dependency/security audit, network crawl, broad test suite, and premium evaluations. docs/review-standards.md is absent. No claim is made that untraced subsystems are clean. One archived child of active epic 33b1f9, ca8ba8, still reports 5/6 checklist steps; current epic rollup treats archived children as complete, so its archived state is preserved as counter-evidence rather than inferred resolved work.
<!-- rcs:coverage:end -->

## Findings

<!-- Findings are append/preserve only; unseen entries are never resolved or removed. -->

<!-- rcs-finding: RCS-Epic-Archive-Link-Guard -->
### RCS-Epic-Archive-Link-Guard - Epic archival can rewrite a linked epic.md target
**Category:** drift
**Subject:** Epic archival can rewrite a linked epic.md target
**Scope:** scripts/skalary/Archive-Epic.ps1 and scripts/skalary/New-Epic.ps1
**Citations:** docs/design-notes/architecture/plan-workflow.design.md:37-39; scripts/skalary/Archive-Epic.ps1:66-71; scripts/skalary/Archive-Epic.ps1:107-119; scripts/skalary/PlanState.psm1:1627-1628; scripts/skalary/New-Epic.ps1:400-404; scripts/skalary/New-Epic.ps1:330-332; scripts/skalary/New-Epic.ps1:73
**Expectation or rationale:** Plan-workflow guidance says Archive-Epic refuses linked sources; the archive flow should not follow a link outside its confined repository while refreshing or moving an epic.
**Current behavior / reachability:** Archive-Epic validates that the epic directory itself resolves physically and that epic.md exists, but it does not validate the physical target or reparse status of epic.md. Inventory reads epic.md through the path. After operator confirmation, Archive-Epic invokes New-Epic to refresh the generated child table; New-Epic rewrites the supplied epic.md path with Set-Content. If epic.md is a file symlink to a writable external file, this refresh follows the link and overwrites its target before the epic directory is moved.
**Impact:** An explicit archive action can overwrite a file outside the repository, violating the documented linked-source guard and physical confinement expectation.
**Exceptions / counter-evidence:** The epic directory itself is checked for physical-path equality, archive destination and child completion gates are enforced, and ShouldProcess requires operator confirmation. Those checks do not validate epic.md or nested entries.
**Uncertainty and coverage limits:** Static source trace; no linked-file fixture was executed. The path flow follows Test-Path/Get-Content/Set-Content at the cited locations; creating a Windows file symlink may require privileges. ArchiveEpic.Tests.ps1 covers completion, active children, destination collisions, and WhatIf but has no linked epic.md case.
**Recommended action:** Route a corrective change through /cip: reject reparse/link targets for epic.md and moved epic entries before New-Epic refresh, and add a temporary-repository regression test proving a linked epic.md is refused without changing its target. Preserve the existing operator confirmation gate.
**Benefits:** Prevents an archive-triggered write through a linked epic file and aligns the implementation with the documented archive guard.
**Tradeoffs:** Adds focused path validation and a link-capable test fixture; behavior stays unchanged for ordinary epic folders.
**Effort:** 3/10
**Complexity:** 3/10

<!-- rcs-finding: RCS-Epic-33b1f9-Archive -->
### RCS-Epic-33b1f9-Archive - Completed epic 33b1f9 remains in the active epic inventory
**Category:** unfinished-work
**Subject:** Completed epic 33b1f9 remains in the active epic inventory
**Scope:** docs/implementation-plans/epics/2026-08-02-33b1f9-workflow-machinery-hardening
**Citations:** docs/design-notes/architecture/plan-workflow.design.md:37-39; docs/implementation-plans/epics/2026-08-02-33b1f9-workflow-machinery-hardening/epic.md:32-42; scripts/skalary/Archive-Epic.ps1:85-106; scripts/skalary/PlanState.psm1:2444-2576
**Expectation or rationale:** Completed epic indexes move under docs/implementation-plans/archived/epics after their child table is refreshed; Archive-Epic is the existing operator-controlled route.
**Current behavior / reachability:** The epic remains under the active epics directory. Its live rollup is complete (9/9 children complete), all nine child plans are archived, the archive destination is absent, and the epic directory is not a reparse point. The checked-in child table also marks all nine children archived. Archive-Epic has not been run because archival requires a separate operator choice.
**Impact:** The active plan inventory continues to include a completed epic, adding stale work to current navigation and epic selection.
**Exceptions / counter-evidence:** Archived child ca8ba8 has an unchecked finalization step and 5/6 checklist progress; current rollup counts archived children as complete. No conclusion is drawn that the historical step was executed. The epic archive script still needs to refresh its generated child table and recheck live gates.
**Uncertainty and coverage limits:** No Archive-Epic WhatIf or mutation was run before operator selection. The source tree was checked for an existing destination and a linked epic directory; final gates must be rerun if archival is selected.
**Recommended action:** Offer a separate archive decision. If selected, rerun the current gates, invoke Archive-Epic.ps1 for 33b1f9, verify the resulting archived epic path, and only then record the successful handoff. Do not archive during this survey.
**Benefits:** Keeps the active epic inventory aligned with completed work while preserving the full epic record in the canonical archive.
**Tradeoffs:** Moves the epic index out of the active directory; references remain resolvable but operators should use its canonical ID or archived path.
**Effort:** 1/10
**Complexity:** 1/10
## Operator decisions

No operator decisions recorded.

<!-- rcs-decision: RCS-D-0001 -->
### RCS-Epic-Archive-Link-Guard - 2026-10-04 - corrective-plan
**Finding:** RCS-Epic-Archive-Link-Guard
**Disposition:** corrective-plan
**Date:** 2026-10-04
**Rationale:** Operator selected the corrective-plan route; plan 10920d was created, reviewed, and confirmed as a drafted active plan. This records a planning handoff, not a code fix.
**Affected scope:** Prevent linked or reparse epic sources from being refreshed or moved by Archive-Epic.ps1.
**Assumptions:** The confirmed plan criteria and existing archive gates remain authoritative; implementation and regression verification are still pending.
**Revisit when:** After implementation and focused linked-source/archive regression tests; retain the finding as unresolved until behavior is verified.
**Evidence:** docs/repository-maintenance.md#RCS-Epic-Archive-Link-Guard; docs/implementation-plans/standalone-2026-10-04-10920d-epic-archive-link-guard/plan.md:60; docs/implementation-plans/standalone-2026-10-04-10920d-epic-archive-link-guard/assets/requirements.md:7
**Successful handoff:** created: docs/implementation-plans/standalone-2026-10-04-10920d-epic-archive-link-guard/plan.md

<!-- rcs-decision: RCS-D-0002 -->
### RCS-Epic-33b1f9-Archive - 2026-10-04 - archived
**Finding:** RCS-Epic-33b1f9-Archive
**Disposition:** archived
**Date:** 2026-10-04
**Rationale:** Operator selected archival after current completion and archive gates were rechecked; Archive-Epic.ps1 archived the epic and Get-PlanState verified its canonical archived location.
**Affected scope:** Move epic 33b1f9 from the active epic inventory to the canonical archived epic directory.
**Assumptions:** The archive script gate treats archived child plans as complete; child ca8ba8 still shows 5/6 steps and its historical unchecked step is not claimed complete.
**Revisit when:** If new evidence changes the archived state or the unresolved historical checklist item needs separate follow-up.
**Evidence:** docs/repository-maintenance.md#RCS-Epic-33b1f9-Archive; docs/implementation-plans/archived/epics/2026-08-02-33b1f9-workflow-machinery-hardening/epic.md:1; docs/implementation-plans/archived/2026-08-08-ca8ba8-review-corroboration-truth/plan.md:1
**Successful handoff:** archived: docs/implementation-plans/archived/epics/2026-08-02-33b1f9-workflow-machinery-hardening/epic.md
