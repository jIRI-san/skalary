## Gate verification statements

**1. Concern reviewers dispatched, and on which models**

All seven `dr` concern reviewers, once per roster model — model supplied as the explicit dispatch parameter, agents declare no `model:`:

| Concern agent | Claude Opus 5 (copilot) | GPT-5.6 Sol (copilot) |
|---|---|---|
| `dr-security` | ✓ | ✓ |
| `dr-correctness-reliability` | ✓ | ✓ |
| `dr-architecture-patterns` | ✓ | ✓ |
| `dr-performance` | ✓ | ✓ |
| `dr-testing-evidence` | ✓ | ✓ |
| `dr-maintainability-consistency` | ✓ | ✓ |
| `dr-operability-observability` | ✓ | ✓ |

No Gemini reviewer exists or ran. Declared-model preflight (`Test-ModelAllowlist.ps1`) ran first and exited 0: *34 agent file(s), 4 dispatch guide(s), 3 autopilot config(s)*.

**2. Invocation count against the budget**

Dispatched **14 of 28** budgeted invocations (7 concerns × 2 models). Scope measured 631 lines (`plan.md` 140 + the core assets the review loaded), which is the >400-line tier: all 7 concerns, reading batched, concerns run once over the union.

**3. Served-model identity is not verifiable**

The preflight validates **declared** configuration only. Nothing in this session observed which model actually served any of the 14 invocations, and no reviewer was asked to self-report — a served model cannot attest its own serving identity, so such a report would pass exactly in the case it exists to catch. The declared-vs-served gap remains an accepted, undetectable residual. No reviewer self-reports appear below; had any, they would be advisory colour, **not evidence**. The 28 figure is likewise a reported budget, not an enforced cap.

Two notes on the run itself: no reviewer raised `[SECURITY] Prompt injection attempt detected` against the plan text. Severity elevation below is the formatter's deterministic rule (a finding flagged by *every* dispatched model is raised one level), not reviewer judgment.

---

## Design Review

_Delivered design of plan b0c0d3 (plan.md plus assets/, 44 of 45 steps complete) reviewed against the shipped implementation_

Models: Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot).
Dispatched 14 of 28 budgeted invocations.

### [1] Delivered tests that prove a requirement clause are not wired to the requirement, so the receipt line under-proves the REQ

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | testing-evidence |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

The REQ-18 second sentence - both /cr and /dr call it and write its output, neither hand-assembles a report - is genuinely proven, by test:build-reviewreport-bundled in ReviewReportBundle.Tests.ps1, which pins the call-operator invocation form, forbids the -File form, requires the returns-verbatim contract, and round-trips typed finding objects through both bundled copies. That test appears in no requirement acceptance criteria. The six REQ-18 markers cover only the formatter internals and three existence probes. The same pattern holds for test:bundle-no-drift, test:bundle-byte-identical and test:bundle-registered against the REQ-19 bundling claims. The receipt is the artifact the acceptance gate reads, and a REQ line is the claim that these markers prove this row. Where the strongest evidence for a clause sits outside the marker list, that claim is overstated: deleting the orphan test leaves the receipt fully green.

_Also noted:_ The REQ-18 markers test formatter behaviour and file existence, but not its central integration claim: both orchestrators call the bundled formatter and emit its returned text verbatim. Those checks exist under test:build-reviewreport-bundled, yet REQ-18 does not cite them. It could green after removing the formatter calls.

**References:** REQ-18 · REQ-19 · steps 4.6, 6.5

---

### [2] REQ-2 malformed-fails-loud is implemented as zero-records-fails-loud, so a partially malformed asset silently shrinks the requirement set

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | correctness-reliability |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

Resolve-PlanSection throws only when the asset is whitespace-only or when the parsed record count reaches zero. Any individual row that fails the shape test - fewer than MinCell columns, a first cell that misses the REQ-n pattern, a stray pipe - is dropped by Get-PlanSectionRecord and by ConvertFrom-PlanRequirementLine with no signal at all. REQ-2 states the contract as present-but-empty or malformed fails loud; the delivered resolver only implements the all-or-nothing end of it, and test:planstate-resolver-malformed-fails-loud only exercises that end, which is why the marker is green. Most single-row losses are caught downstream by luck rather than design: the sequential-numbering gate fires on a hole in the middle, and the unknown-REQ-reference gate fires if a step still cites the lost id. Neither covers the highest-numbered requirement when no step references it - it simply ceases to exist, taking its typed evidence markers with it, and the gate criterion that the receipt contains no cross mark then passes over a requirement that was never evaluated.

_Also noted:_ Resolve-PlanSection rejects an asset only when it yields zero valid records. A file containing one valid row plus malformed or duplicate rows passes; malformed rows disappear and duplicate IDs are silently overwritten by ConvertFrom-PlanRequirementLine or ConvertFrom-PlanRiskLine. Conversely, divergence compares sorted normalized row arrays, preserving duplicates, rather than the keyed records consumers receive. Thus identical parsed metadata can falsely diverge, while conflicting duplicate records can silently resolve. REQ-2 defines divergence as inequality over the normalized parsed record set - round-2 finding 8. What shipped compares raw normalized rows.

**References:** REQ-17 · REQ-2 · evolution-log round 2 finding 8 · scripts/skalary/PlanState.psm1 · steps 1.3, 1.4 · tests/skalary/PlanAssets.Tests.ps1

---

### [3] Step 10.5 mandates npm run eval, but no evidence marker covers it, so its two failures survive only in a log the run own contract calls ephemeral

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | operability-observability · testing-evidence |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

Step 10.5 requires the ordered pipeline to end with npm test and npm run eval. The REQ-17 evidence markers cover test:unit and test:validate-all and stop there - requirements.md has no eval marker, and evidence.md accordingly says nothing about it. The eval suite in fact finished red: 116 pass and 2 fail is recorded once, in assets/logs/capture.md, together with the judgment that both failures predate the branch. That judgment may well be right, but autopilot.agent.md explicitly declares mid-run capture ephemeral only. So the only durable statement about the eval suite state at the acceptance gate is a line in a file the system treats as disposable, inside a plan folder about to be archived. The definition of done in intent.md says npm test green and never mentions the eval suite, so intent and requirements agree with each other and both omit a command the plan step requires.

_Also noted:_ Step 10.5 is complete, but the capture log records npm run eval at 116 pass and 2 fail. Neither test:unit nor test:validate-all runs Test-Evals.ps1, and no typed marker records the failure or an explicit deferral. The phase therefore closed without satisfying its pipeline or proving the RISK-8 mitigation.

_Also noted:_ capture.md records npm run eval at 116 passed and 2 failed, yet step 10.5 is complete, REQ-17 requires the result to be green, and neither Decisions nor the evidence receipt carries a formal deferral. A later operator sees passing evidence unless they inspect the run log manually.

**References:** REQ-17 · RISK-8 · step 10.5 · steps 10.5, 10.6

---

### [4] The acceptance gate own pass condition is unreachable, and nothing in the plan closes the loop after it

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | operability-observability · testing-evidence |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

The step 10.7 Verify block requires that assets/evidence.md contains no cross mark, but the only two cross-marked entries in the receipt are review:dr (REQ-9) and review:cr (REQ-17) - the two markers that 10.7 itself produces. The receipt was last built by 10.6, which is after 10.5 and 1.7 and therefore necessarily ran before the reviews existed. There is no step 10.8, and no after-10.7 edge anywhere, that rebuilds the receipt once the reviews land. The gate is therefore evaluated against a receipt guaranteed to contradict its own acceptance criterion at the moment the operator reads it. Closure is left to the /ci archival gate, which is process machinery outside the plan and carries no dependency edge to 10.7 - so the plan last requirement can only go green through a step the plan never declares. Compounding it: assets/decisions.md contains no deferral keyed by REQ ID for either review marker, which is the exact escape hatch the crosscheck guide names. As written, the plan has no legal terminal state.

_Also noted:_ Step 10.7 runs cr and dr, but neither skill persists evidence or rebuilds the receipt. Test-Plan.ps1 deliberately skips review markers, while Build-EvidenceReceipt.ps1 requires a caller-supplied result. Consequently assets/evidence.md still records gate-1 review:cr as unrun, and this run cannot make review:dr pass through the documented Steps.

**References:** REQ-17 · REQ-9 · assets/decisions.md · step 10.6 · step 10.7

---

### [5] The dr concern tier is keyed on plan lines, and the assets split shrank that number by about 75 percent - a migrated plan now reads as the cheapest tier

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | performance |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

The size-scaled concern tier selects 3 concerns (6 invocations) at 150 lines or fewer, 7 concerns (14) at 151 to 400, and 7 with batched reading above 400. For dr the input variable is plan lines - and nothing in the delivered payload defines which lines. plan-scope-guide.md says only measured in lines, while its own section 2 says the opposite of what the tier assumes: under the assets layout, plan.md alone is not the plan. DispatchGuide.Tests.ps1 asserts the literal threshold strings against literals in the test, so nothing resolves the ambiguity. The thresholds were authored against the monolith, where line count was a genuine proxy for review surface. This plan then moved the requirement table, risk table, decisions, intent, references and evolution log out of plan.md, and the delivered plan.md is 140 lines - a 45-step, 21-requirement, 12-risk plan that lands in the cheapest tier and is entitled to 3 concerns and 6 invocations. The plan own acceptance step 10.7 expects a 7-concern fan-out, which is the tier the pre-split line count would have produced. The RISK-4 mitigation therefore now fires in the wrong direction: the layout change silently halved review coverage for every plan that adopts it.

_Also noted:_ The shipped tier uses plan.md line count, but under the assets layout that file excludes requirements, risks, decisions and intent. This plan plan.md falls near the 150-line small tier while its mandatory review material pushes the real design well beyond 150 lines. Extraction therefore reduces six-invocation eligibility without reducing review context.

**References:** REQ-9 · RISK-4 · step 10.7 · step 4.4 · steps 4.4, 6.2

---

### [6] The learnings cap destroys the entries it claims to fold, and this run lost 10 of its own 18 learnings with no recoverable trace

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | operability-observability |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

Invoke-LearningsCap removes the oldest entry lines outright and replaces them with a single line whose entire content is a count. No text, no step ids, no triggers - the summary summarizes nothing. The delivered evidence is this plan own log: assets/logs/learnings.md now holds exactly one line for phases 1 through 7, reading that 10 additional learnings were folded into this summary. Ten reusable patterns harvested across seven phases of a plan that rewrote the plan and review toolchain are gone, and because Add-WorkflowNote rewrites the file in place, they exist only in whatever intermediate commit happened to capture them. The line is also misfiled: it carries step token 8.1 but sits under Phase 1, so a reader cannot even tell which phase the destroyed entries came from. This is not a cosmetic loss - learnings.md is a named /si harvest source in REQ-14 and in harvest-guide.md, so the self-improvement loop the plan exists to build can never read the majority of what this plan learned. The cap is a legitimate context-cost control, but it should be lossless from the operator point of view.

_Also noted:_ The ten-entry cap removes old learning text and replaces it only with a count. The delivered learnings.md says ten learnings were folded into this summary, but contains no summary of their content. Those lessons are therefore unavailable to /si and to post-run diagnosis.

**References:** REQ-14 · REQ-20 · assets/logs/learnings.md · step 8.1 · steps 1.6, 8.1

---

### [7] The plan-assets layout is a contract with no owner and no gate, and non-/ci writers already violate it in the delivered tree

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | architecture-patterns · maintainability-consistency |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

plan-assets-layout.md states plan.md is the ONLY file at plan-folder root, and intent.md repeats it as a desired outcome. Nothing enforces it: Test-Plan.ps1 has gates for evidence, human-step detail and phase budget but none for layout, and Get-PlanLayout only sniffs for assets/requirements.md. The plan folder under review already breaks the contract - transcripts/ sits at the root beside plan.md, written by all three autopilot launchers, which build the path by string concatenation and never call Resolve-PlanAssetPath. The root cause is that REQ-20 enumerated writers by name instead of establishing that every plan-folder write goes through Resolve-PlanAssetPath as the rule and then finding the writers. The same gap shows on the read side: PlanAssetMap is a closed ValidateSet of eleven kinds, so any new plan-folder artifact - transcripts/, and assets/reviews/ created for this very gate - has no way to be layout-resolved and simply lands wherever its author typed. The shipped plan-template.md also omits assets/evolution-log.md, a kind the resolver does know about.

_Also noted:_ REQ-1 requires every plan artifact except plan.md to live under assets/, but the delivered plan contains a root-level transcripts/ directory. This is systemic: autopilot host and container launchers explicitly write transcripts there. The tests validate the template and initial scaffold, not the maintained folder invariant, so execution immediately drifts from the design and intent.

_Also noted:_ REQ-1 and the layout decision place all non-plan.md content under assets/, but host and container autopilot write transcripts/ beside it. The delivered plan contains ten such files. Existing tests validate only the template, so this drift passes.

**References:** REQ-1 · REQ-17 · REQ-20 · assets/decisions/plan-assets-layout.md · assets/intent.md desired outcome · step 1.6 · steps 1.1, 1.6, 10.4 · steps 1.1-1.7

---

### [8] Two design notes shipped by this plan are absent from both discovery indexes, and the index-integrity test cannot catch it

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | maintainability-consistency |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

The delivery added docs/design-notes/explorations/asset-scanner-root-bound.design.md and review-system-enforcement-gaps.design.md. Neither has a row in the root index table in .design-notes.md, and neither appears in the Active Explorations table in explorations-and-experiments.design.md, which still lists only container-autopilot-watchdog. The root index own Adding a New Skill procedure makes the table row mandatory, and the note stated loading model is that the index is the discovery layer - so both notes are unreachable by the documented mechanism. review-system-enforcement-gaps is the distilled record of the 44-finding gate-1 review and declares globs over the two review plugins and Build-ReviewReport.ps1; it is precisely the note a future change in this area needs, and it will never be loaded. Nothing gates this. DesignNotes.Tests.ps1 asserts index rows for individually named notes rather than the invariant that every design note on disk has a row, so each new note needs a bespoke assertion someone must remember to write.

_Also noted:_ review-system-enforcement-gaps.design.md is absent from both the root design-note index and the active-explorations table, with no inbound design-note reference. Agents following the documented discovery strategy cannot find this recorded guidance.

**References:** REQ-17 · assets/intent.md definition of done · step 10.4 · step 10.4 (REQ-17)

---

### [9] Update-FeedbackQueue truncates operator verdicts at 300 characters with no marker, and all three of this gate recorded verdicts are cut off mid-word

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | operability-observability |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

ConvertTo-SafeFeedbackText applies a hard 300-character cut with no ellipsis, no truncation flag on the returned object, and no warning to the caller. The delivered docs/feedback/queue.md shows the result: all three recorded verdicts for this plan end mid-word. Two of the three are MISS findings, and both are severed at precisely the point where the substance would have been. The second entry names a real delivery gap - both dispatch guides invoke scripts/skalary/Test-ModelAllowlist.ps1, which no plugin bundles - and then stops before stating what the guides own or what the operator wanted done about it. The script own header says this record has to survive the session that produced it. A silently halved record does not survive it. This compounds with /si, which harvests the Recorded section as a primary source: the loop reads half-sentences and cannot tell they are half-sentences. The sanitization goals do not require a length cap at all - length neither forges a field nor breaks the entry grammar.

_Also noted:_ Update-FeedbackQueue.ps1 cuts responses at 300 characters without rejecting them or marking truncation. All three b0c0d3 records in queue.md end mid-sentence or mid-word, so /si receives incomplete corrections while the queue reports successful durable writes.

**References:** REQ-13 · REQ-14 · steps 7.1, 7.2 · steps 7.1, 8.1

---

### [10] copilot-customizations.design.md still documents the pre-assets monolithic plan format and a /ci flow without the gates this plan added

| | |
|---|---|
| **Severity** | Critical (elevated - flagged by every dispatched model) |
| **Concerns** | maintainability-consistency |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

copilot-customizations.design.md carries a Plan file format block showing Decisions and Requirements tables living inside plan.md - exactly the layout REQ-1 removed. The same section cip flow step 4 still reads: Draft plan, Decisions log plus Requirements table plus Risks table plus Phases. Its New-Plan.ps1 bullet describes scaffolding plan.md with no mention of assets/, and its numbered ci flow has no intent read (REQ-4), no on-demand asset loading (REQ-3), and an archival gate with no /pfb offer (REQ-13) or /si offer (REQ-14) - even though the note own file-inventory table above it correctly describes /pfb as offered at the /ci archival gate. The note therefore contradicts itself internally and contradicts plan-workflow.design.md, which is the note that actually owns the layout and documents it correctly. This is a second source of truth for the plan-file format, and it is the stale one. It also survives the gates: the REQ-17 marker for this file is a contains match on the word concern, and test:design-note-drops-orchestrator-fence only asserts the fence and roster text.

_Also noted:_ autopilot.agent.md instructs agents to parse Requirements and Risks tables from plan.md. copilot-customizations.design.md likewise shows inline Decisions, Requirements and Risks and says /cip refines plan.md. These contradict the shipped template and can reintroduce the retired layout.

**References:** REQ-17 · REQ-3 · assets/intent.md definition of done · step 10.4 (REQ-17) · steps 1.5, 10.4

---

### [11] Shared review assets use a second duplication mechanism that contradicts the repo documented managed-duplication pattern

| | |
|---|---|
| **Severity** | High (elevated - flagged by every dispatched model) |
| **Concerns** | architecture-patterns |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

plugin-registry.design.md records the pattern for files that must exist in more than one place: bundled copies are generated, not hand-authored - scripts/skalary/ is the single source of truth and Sync-PluginScripts.ps1 is the only writer, with a -WhatIf drift gate proving byte-equality. The three shared review assets - dispatch-guide.md, collation-guide.md, concern-ledger-map.md - do not use it. Both copies are hand-authored under the cr and dr plugins, neither is marked canonical, no generator writes either one, and equality is only detected afterwards by ReviewSkills.Tests.ps1 and DispatchGuide.Tests.ps1. The assets nevertheless describe themselves in the language of the generated pattern: byte-identical by construction, edit one and the drift gate fails until both match. By construction is what Sync-PluginScripts gives; what shipped is by assertion, and the recovery action is a human hand-copy with no defined direction. Step 10.2 extended the scanner to see markdown assets but never extended it to own them.

_Also noted:_ The code-review and design-review plugins each own separate source copies of dispatch-guide.md, collation-guide.md and concern-ledger-map.md. Tests compare their content after authorship, but no generator or canonical shared source produces both copies. Sync-PluginScripts.ps1 only generates deterministic script bundles and does not manage these Markdown assets. This contradicts the promised one definition and byte-identical by construction architecture.

**References:** REQ-10 · REQ-9 · assets/decisions/reviewer-fanout.md · steps 4.4, 6.2 · steps 4.4, 6.2, 10.2

---

### [12] The REQ-6 behavioural clause is proven by a bare substring, alone among its peers

| | |
|---|---|
| **Severity** | High (elevated - flagged by every dispatched model) |
| **Concerns** | testing-evidence |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

REQ-6 asserts that /cip consults the index - not the plans - before drafting. The only marker covering that clause is a contains match on interview-guide.md for Get-PlanIndex, which under PlanEvidence.psm1 is a regex match count greater than zero - satisfied by any mention whatsoever, including a consider-running, a deprecation notice, or an example inside a fenced block. PlanIndex.Tests.ps1 ships exactly two It blocks, and neither reads the interview guide. This is the outlier, which is what makes it a finding rather than a stylistic note: every sibling skill-behaviour clause in this plan got a prose-pinning test - test:ci-loads-assets-on-demand pins three phrases and asserts dogfood-copy equality; test:ci-reads-intent runs five cases; test:concern-ledger-map-total checks all four harvest mirrors. Step 3.2 alone was left on a substring.

_Also noted:_ REQ-6 proves the index works and that the interview guide contains Get-PlanIndex. That substring can coexist with instructions to open plans directly, so the negative index-not-plans contract cannot fail.

**References:** REQ-6 · step 3.2

---

### [13] The RISK-3 mitigation is verified nine phases after the phase that owns it, and the intent second success signal has no test of its own

| | |
|---|---|
| **Severity** | High (elevated - flagged by every dispatched model) |
| **Concerns** | testing-evidence |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

The RISK-3 mitigation reads: plus run the validator over every existing plan before Phase 1 completes, scoped to steps 1.2, 1.3 and 1.4. No marker on REQ-2 does that. The nine REQ-2 markers compare parsed metadata and assert corpus layout stability, but never invoke Test-Plan.ps1. The one test that runs the validator over the corpus, test:migrated-plan-validates, skips legacy plans by construction - precisely the population RISK-3 is about. The only corpus-wide validator run is inside validate.ps1, reachable through test:validate-all - a marker on REQ-17, in Phase 10. Phase 1 could therefore have closed green with legacy-plan validation regressed, surfacing nine phases later attributed to the wrong requirement. This also answers the intent question directly: the success signal that legacy and archived plans keep validating byte-for-byte unchanged is not established by any single test. What exists is parsed-record parity on synthetic twins, a corpus assertion that legacy plans still resolve as legacy, and a Draft-stage exit code from validate.ps1 where plan-file evidence is non-blocking. Nothing pins the archived plan files as unmodified artifacts.

_Also noted:_ The intent requires legacy and archived plans to remain byte-for-byte unchanged. test:planstate-legacy-layout-unchanged only proves current files parse through the legacy path; parity tests compare generated fixtures. Neither detects edits to historical plan bytes.

**References:** REQ-2 · RISK-3 · assets/intent.md success signal 2 · intent success signals · step 1.4

---

### [14] The assets layout stated per-step saving did not land on its dominant term: requirements are still read on essentially every step, and intent is a new unconditional read

| | |
|---|---|
| **Severity** | High (elevated - flagged by every dispatched model) |
| **Concerns** | performance |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

plan-assets-layout.md justifies the split with the claim that /ci reads the whole plan.md on every step, so risk prose and requirement rationale are re-read hundreds of times for work that touches neither. Measured against what shipped, the read set per step is: plan.md (140 lines, still read whole), plus assets/intent.md - which ci/SKILL.md marks always and execution-guide.md re-mandates as the first read of every step loop - plus assets/requirements.md whenever the step has a REQ ref, which is 45 of 45 steps in this plan. Read granularity is per file, not per record, so validating the acceptance criteria of the step REQ refs pulls all 21 rows, roughly 12 KB - exactly the bulk the split was supposed to stop re-reading. What genuinely left the hot path is risks, decisions, references and the evolution log; the single largest asset stayed, and a new mandatory read was added on top. Nothing in the delivered tests measures per-step context - test:ci-loads-assets-on-demand asserts a string appears in SKILL.md - so the promised reduction is unverifiable in either direction.

_Also noted:_ The model-context reduction largely materialized: /ci reads intent every step and requirements or risks only when needed. Machine I/O did not. Every Get-PlanState call invokes Get-PlanMetadata, which reads plan.md and unconditionally resolves and reads requirements, risks and decisions. The step loop reruns this each step, turning one monolithic read into four repeated reads. The acceptance test only checks that the skill contains on-demand prose.

**References:** REQ-3 · steps 1.3, 1.5 · steps 1.5, 1.7

---

### [15] The plan only human gate carries a Rollback for the plan, not for the gate, and the human-step-detail check cannot tell the difference

| | |
|---|---|
| **Severity** | High (elevated - flagged by every dispatched model) |
| **Concerns** | operability-observability |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

The step 10.7 Steps block mutates state that its Rollback block does not mention: step 4 installs the touched plugins into a scratch clone, step 6 stages a throwaway edit to .github/workflows/registry-ci.yml on a branch, and steps 1 and 2 run cr branch and /dr, which under the delivered wiring can append to docs/review-ledger/ and docs/feedback/queue.md. The Rollback says only: git revert the phase commits, no external state is mutated - a statement about the ten implementation phases, copied into the one step where it is not true. An operator who runs the gate and stops has a scratch clone with installed plugins, a branch carrying a staged workflow edit, and possibly new queue and ledger rows, with nothing telling them to clean any of it up. The three truncated entries in queue.md were written by gate runs, not by a phase commit, and no phase revert removes them. REQ-5 exists precisely to make the operator round-trip single-pass, and the delivered gate checks presence only, so a Rollback that is correct prose about the wrong subject passes.

_Also noted:_ Step 10.7 mutates a scratch clone, creates or uses a branch, scaffolds a throwaway plan, installs plugins, and stages a workflow edit. Its Rollback instead says to revert unspecified phase commits, provides no commit range, and does not clean up any acceptance-test state.

**References:** REQ-5 · RISK-7 · step 10.7

---

### [16] The review:cr and review:dr markers carry no pass predicate, and they are the sole non-prose proof for REQ-9

| | |
|---|---|
| **Severity** | High (elevated - flagged by every dispatched model) |
| **Concerns** | testing-evidence |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

crosscheck-guide.md defines the marker as: verify the relevant review run reports no remaining findings for the claimed class - and class is defined nowhere. The gate-1 cr branch run returned 44 findings; almost none are about the REQ-17 claim, so an operator can record the REQ-17 review:cr as passed or failed with equal justification and no rule to appeal to. A marker whose verdict is unconstrained is not typed evidence. This matters more for REQ-9 than for REQ-17. REQ-17 also carries test:unit and test:validate-all. REQ-9 states runtime orchestrator behaviour - dispatch once per model via explicit parameter, scale by size, run once over the union, report against the budget - and its other four markers all assert substrings in dispatch-guide.md. Only the second declared-model-preflight case executes anything. So REQ-9 reduces to: the guide says the right words, plus one unbounded judgment call.

_Also noted:_ The REQ-9 tests regex-match dispatch-guide.md. They remain green if either orchestrator stops dispatching once per model, ignores scaling, or runs per batch. The round-1 vacuous-marker fix therefore did not fully survive as behavioural evidence.

**References:** REQ-17 · REQ-9 · crosscheck-guide.md · evolution-log round 1 finding 4 · steps 4.4, 6.2

---

### [17] The scaffolds array extends the install-confinement boundary but was recorded only below the architecture tier

| | |
|---|---|
| **Severity** | High (elevated - flagged by every dispatched model) |
| **Concerns** | architecture-patterns |
| **Models** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |

asset-bootstrap.md reasons directly about ARCH-Install-Confinement and answers it with a new mechanism: a machine-readable scaffolds array, with two declared modes, naming the runtime paths outside .github/ a plugin is sanctioned to create at first use - and it now travels to consumers through registry.json, which required widening a schema that set additionalProperties false. That is an interface-level extension of the install and bootstrap boundary and a new declared extension point on the plugin manifest, delivered across plugin.schema.json, registry.schema.json and six plugin manifests. It was recorded in a plan-local decision record and in plugin-registry.design.md, but arch-install-confinement.md and its contract JSON were not touched. The arch note still describes repo-level scaffolding as generically prompt-driven at first use with no mention of the declaration, the modes, or the confine-helper requirement - and the maintenance protocol makes updating the note part of the same change. The cost is concrete: the arch tier is the one index /cip, /ci and every concern reviewer auto-load, so the next plan reasoning about install confinement sees the prohibition without the sanctioned escape hatch, and is likely to re-derive a post-install hook - the exact option this decision record rejected.

_Also noted:_ The scaffolds array establishes a new first-use write contract for paths the installer is forbidden to materialize. It extends the operational boundary around ARCH-Install-Confinement, but its rationale and modes exist only in the plan-local decision and the implementation-level plugin-registry note. The architecture index still has no active ADR, and the confinement contract does not describe the scaffold boundary or its ownership requirements. That violates the architecture-tier same-change maintenance protocol and leaves future plans without always-loaded context for this exception.

**References:** ARCH-Install-Confinement · REQ-19 · RISK-9 · assets/decisions/asset-bootstrap.md · step 10.3 · steps 10.3, 10.4

---

### [18] A forward [after:] edge deadlocks step selection permanently, and nothing in the delivered validator prevents authoring one

| | |
|---|---|
| **Severity** | High |
| **Concerns** | correctness-reliability |
| **Models** | Claude Opus 5 (copilot) |

Get-NextStep takes the first non-complete step in document order and, if its After set is unmet, returns BlockedByAfter without advancing. So a step wired after a later step is a terminal stall: the blocker can never be reached because selection never moves past the blocked step. Test-Plan.ps1 validates the token shape and existence and runs cycle detection, but has no rule that an after target must precede its step in document order - cycle detection does not catch a plain forward edge. The epic layer solves the analogous problem by skipping blocked children; the step layer deliberately does not, and the gap is unguarded. Round-2 finding 3 in the evolution log is exactly this class - since /ci picks the first incomplete step in document order, the failing order was the one that would execute - and it was resolved by hand-swapping 1.6/1.7 rather than by adding the gate, so the defect class survived into delivery with no detector. The delivered /ci compounds it: on blocked-by-after it tells the agent to resolve the dependency or pick eligible work itself, which contradicts the same file State authority rule and hands ordering back to model judgment - in container-autopilot mode, with no operator present.

**References:** REQ-2 · REQ-3 · evolution-log round 2 finding 3 · scripts/skalary/Test-Plan.ps1

---

### [19] Plan-completion harvest wrote ledger entries from phase 10 only, and nothing reports harvest coverage, so nine phases of lessons vanished silently

| | |
|---|---|
| **Severity** | High |
| **Concerns** | operability-observability |
| **Models** | Claude Opus 5 (copilot) |

Every one of the twelve plan-b0c0d3 entries across docs/review-ledger/ carries the phase-10 tag. Phases 1 through 9 contributed nothing, despite cr-log.md recording roughly sixty code-review findings across those phases and the surviving phase-8 and phase-9 learnings naming exactly the kind of cross-plan rule the ledger exists for. The cause is structural: harvest runs once at plan completion inside the final phase context window, and autopilot.agent.md states you have a fresh context window for each phase while asking the agent to distil one-line lessons from the layout-resolved logs, with no coverage obligation and no reporting. What makes this an operability defect rather than a judgment call is that the shortfall is invisible. The harvest contract emits no receipt: no count of source log entries considered versus ledger entries appended, no per-phase coverage line, and the no-op handling makes a harvest that produced nothing indistinguishable from one that ran and found nothing worth keeping. A fully skipped harvest is silent too. There is also no evidence marker on the harvest step, so the crosscheck cannot see it either.

**References:** REQ-10 · REQ-14 · docs/review-ledger/ · step 8.3

---

### [20] REQ-12 sells the skill split as CLI-usable, but the delivered dispatch contract is VS Code-only

| | |
|---|---|
| **Severity** | High |
| **Concerns** | architecture-patterns |
| **Models** | Claude Opus 5 (copilot) |

The REQ-12 stated reason for moving orchestration out of cr.agent.md and dr.agent.md into skills is that skills are CLI-usable - ReviewSkills.Tests.ps1 encodes that as the skill, not the agent, is what a CLI run can execute. What shipped inside the skill is bound to one host. dispatch-guide.md mandates the qualified Model Name (vendor) form used by VS Code-hosted agents, the entire model-resolution rationale is the VS Code explicit-param then frontmatter then parent ordering, and model-allowlist.psd1 maps all sixteen cr and dr agents to VSCode. A /cr run under Copilot CLI therefore has no legal roster: every model name the guide tells the orchestrator to pass is a name the preflight would reject for a CLI-hosted agent, and there is no host branch anywhere in the guide or the skill. This is precisely the two-format discipline the plan built for the allowlist - host is not inferable, never normalize the two forms - applied to the declaration but not to the consumer that acts on it. The tell is the CLI fallback entry in the allowlist: a CLI dispatch path was anticipated in the data model and never built, so that entry is unreachable today.

**References:** REQ-12 · REQ-7 · REQ-9 · steps 4.1, 4.4, 6.1-6.3

---

### [21] Reviewer context cost is unbounded despite bounded invocation count

| | |
|---|---|
| **Severity** | High |
| **Concerns** | performance |
| **Models** | GPT-5.6 Sol (copilot) |

REQ-11 makes every selected CR reviewer independently read the complete changed-file union, architecture index, design-note index and matched notes. The 15-file batch bound limits list shape, not total files, bytes, tokens or file size; batching also does not reduce the union each of up to 14 invocations must inspect. The delivered cost model therefore bounds invocation count while leaving per-invocation and total credit cost unbounded.

**References:** REQ-11 · REQ-9 · RISK-4 · steps 4.4, 5.2

---

### [22] Scaffold confinement does not resolve symlink escapes

| | |
|---|---|
| **Severity** | High |
| **Concerns** | security |
| **Models** | GPT-5.6 Sol (copilot) |

New-Plan.ps1, New-Epic.ps1, Add-LedgerEntry.ps1 and Remove-LedgerEntry.ps1 use lexical GetFullPath prefix checks only. Existing symlink or junction components can redirect their declared scaffold writes outside the repository. Tests verify only that the named helper exists and is called, not that it rejects symlink escapes. This re-erodes round-1 finding 14: the scaffold contract requires a canonicalize-then-confine helper, and what shipped canonicalizes lexically.

**References:** REQ-19 · RISK-9 · assets/decisions/asset-bootstrap.md · steps 1.2, 9.1, 10.3

---

### [23] The /si write allowlist admits host-executed, credential-handling code under plugins/ - the executability threat model stops at .github/workflows/

| | |
|---|---|
| **Severity** | High |
| **Concerns** | security |
| **Models** | Claude Opus 5 (copilot) |

RISK-12, DR round 2 finding 1, and the shipped guard all reason about executability as a property of .github/: Test-SiWriteScope.ps1 denies .github/workflows/ and .github/actions/ ahead of an allowlist of plugins/, docs/, .github/skills/, .github/agents/, .github/prompts/, and self-improvement.design.md justifies the denylist solely by ".github/ holds executable workflows, not only documents." plugins/ is characterized throughout as "the customizations themselves". The delivered tree does not match that characterization. plugins/autopilot/scripts/ contains get-credential.ps1, which reads a fine-grained PAT out of Windows Credential Manager and returns it in cleartext, alongside prepare-env-file.ps1, host-command.ps1, container-entrypoint.sh and devcontainer/Dockerfile - code that runs on the operator host or inside the autopilot container with those credentials present. All of it is inside the allowlist, unguarded. The same is true of every bundled plugins/*/skills/*/scripts/*.ps1 and its .github/skills/*/scripts/ twin. The guide own denial table makes the inconsistency explicit: it denies scripts/ on the rationale that a code change belongs in a plan, while plugins/ - which carries strictly more dangerous code than scripts/skalary/ does - is blanket-allowed. This is design-vs-delivery drift, not a re-litigation of the DR-2 fix: the fix correctly narrowed .github/, and nobody re-asked the question one directory over.

**References:** REQ-14 · RISK-12 · RISK-6 · step 8.2

---

### [24] The concern-split review architecture never reached the autonomous path, which still carries a second, older taxonomy

| | |
|---|---|
| **Severity** | High |
| **Concerns** | architecture-patterns |
| **Models** | Claude Opus 5 (copilot) |

The plan replaced per-model reviewers with seven concern reviewers and a deterministic concern-to-ledger map so that /ci harvest stops being judgment-based (REQ-10). The autonomous execution path did not follow. autopilot.agent.md step 17 still invokes the built-in code-review subagent, and step 18 emits a hand-written review-hints block whose six buckets - Security, Correctness, Concurrency, Architecture, Performance, Style - are a different taxonomy from the seven concern ids the map is keyed on. Yet the same file harvest section instructs the agent to select the ledger category by the concern that raised the finding, through concern-ledger-map.md. The map input therefore does not exist on this path: an autopilot run must invent a concern id to look up, which is the judgment call REQ-10 was written to remove, and every finding is logged with the same source tag regardless. Structurally this leaves the repo with two review architectures for the same job, with the concern taxonomy duplicated across them and nothing keeping them aligned. Step 8.3 wired the map into the autopilot mirror but not the reviewers that produce its keys, so the change looks complete to test:concern-ledger-map-total while the pipeline it feeds is unchanged.

**References:** REQ-10 · REQ-8 · assets/decisions/concern-taxonomy.md · steps 4.2, 8.3

---

### [25] The dr batching contract makes the requirements asset both a batch and mandatory shared context in every other batch, so the largest asset is re-read once per batch

| | |
|---|---|
| **Severity** | High |
| **Concerns** | performance |
| **Models** | Claude Opus 5 (copilot) |

plan-scope-guide.md gives every assets file its own batch and requires that every batch carries the same shared context: the requirements and risks tables, the intent and the loaded design notes. Those two rules compose badly: the requirements table is simultaneously one batch and a mandatory rider on all the others, so it is delivered once per batch inside a single reviewer invocation. For this plan that is 10 phase batches plus roughly 7 asset batches, carrying a requirements table of about 12 KB plus risks and intent - on the order of 300 KB of duplicated shared context per invocation, multiplied again by the 14 invocations of the full tier. The growth term is phases times assets, and neither factor is bounded anywhere: cr got an explicit 15-file batch bound, dr got no equivalent cap on batch count or shared-context bytes. The decision record justification for batching - that it splits reading, never concern passes, so cost stays linear - does not hold once the shared context is re-attached per batch.

**References:** REQ-9 · RISK-4 · steps 4.4, 6.2

---

### [26] The evidence-marker grammar promises a regex but the table-cell parser has no pipe escape, so alternation silently truncates the assertion

| | |
|---|---|
| **Severity** | High |
| **Concerns** | correctness-reliability |
| **Models** | Claude Opus 5 (copilot) |

Split-MarkdownTableCells splits a requirements row on every pipe with no escape handling, and ConvertFrom-PlanRequirementLine then takes cell 2 as the acceptance criteria and cell 3 as the Steps column. Get-TypedEvidenceMarkers reinforces this by terminating every marker value at a pipe. But the file-contains marker is documented and implemented as a real .NET regex - PlanEvidence.psm1 compiles it - and alternation is the most natural thing an author writes in one. A marker whose contains value uses alternation parses as only its first branch, the tail becomes the Steps cell, the real Steps cell is dropped, and Build-EvidenceReceipt reports a tick for an assertion strictly weaker than the one authored. Nothing warns: no gate checks cell count, checks the Steps cell shape, or rejects a pipe inside a criteria cell. This is not hypothetical. The delivered scaffold ships a row that hits it: the New-Plan.ps1 requirements.md placeholder ends with a review:cr-pipe-dr marker inside the criteria cell, so every newly scaffolded plan starts with a five-cell REQ-1 whose Steps column is a literal fragment. The same literal is published as the marker vocabulary in both guides.

**References:** REQ-1 · REQ-2 · drafting-guide.md · scripts/skalary/New-Plan.ps1 · scripts/skalary/PlanState.psm1

---

### [27] test: markers are outside the machine-checked evidence path entirely - nothing binds a marker id to a test that exists

| | |
|---|---|
| **Severity** | High |
| **Concerns** | testing-evidence |
| **Models** | Claude Opus 5 (copilot) |

This is the structural successor to round-1 finding 4. The replacement markers are substantive - REQ-2, REQ-14, REQ-19, REQ-11 and REQ-18 walk down to real behavioural assertions over temp-dir fixtures, corpus walks with explicit anti-vacuity guards, and process-level exit-code checks. The problem is the binding, not the content. Test-Plan.ps1 explicitly continues on any marker starting with test:, so the validator verifies exactly one marker family - the file family - and that family is the decorative one. Every substantive proof in all 21 requirements is a test marker resolved by an agent reading crosscheck-guide.md prose, and no script maps a marker id to a Pester It block. The consequence is concrete: rename or delete an It and the Pester filter matches zero cases; the guide fail-if-missing rule is honoured only by agent diligence, and the receipt grammar has a slot for N cases passed with no rule requiring N to be at least 1. All 96 test markers currently resolve to at least one real It - but that is an observation about this run, not a property the system holds.

**References:** Test-Plan.ps1 marker dispatch · all test: markers REQ-1..REQ-21 · crosscheck-guide.md

---

### [28] ADR harvest bypasses the shared layout resolver

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | correctness-reliability |
| **Models** | GPT-5.6 Sol (copilot) |

Import-ArchAdr.ps1 selects assets/decisions/ when that directory exists and otherwise reads root decisions/. It never calls Resolve-PlanAssetPath with the decision-records kind, contrary to the REQ-20 shared-resolver contract, which names the ADR-harvest guidance explicitly. A legacy plan containing an incidental assets/decisions/ directory can have its authoritative root records ignored; an assets-layout plan missing that directory can harvest stale root records. Existing REQ-20 tests cover logs, receipts and static path state, but not ADR harvest behaviour.

**References:** REQ-20 · evolution-log round 1 finding 7 · step 1.6

---

### [29] Fence integrity for harvested text rests entirely on a model-generated random id; all three storage-time sanitizers pass angle brackets through

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | security |
| **Models** | Claude Opus 5 (copilot) |

harvest-guide.md states the problem accurately - Add-LedgerEntry and Update-FeedbackQueue neither strips angle brackets, so a record can contain a literal end marker - and answers it with two controls the model must execute: generate a fresh unpredictable id per source, and scan raw source text for the token UNTRUSTED_INPUT before wrapping. Both are prose. The guide itself concedes that this scan is the only place the forgery can be caught. The delivered sanitizers confirm the gap and show how cheaply it closes. Update-FeedbackQueue.ps1 neutralizes newlines, control characters, brackets, backtick and pipe; Add-LedgerEntry.ps1 strips brackets, parentheses, comma, hash, pipe and the field grammar; Add-WorkflowNote.ps1 does the same. Each already owns a character-class denylist at the only write path into its file, and none includes the angle brackets. Adding them - or rewriting a literal UNTRUSTED_INPUT token at write time - moves fence integrity from a model-behaviour dependency to a deterministic one, for the exact three writers that produce all four harvest sources.

**References:** REQ-14 · RISK-10 · step 8.1

---

### [30] Get-PlanIndex degrades silently: an unparsable plan drops out of the index, exit code stays 0, and no consumer is told to read the error list

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | correctness-reliability |
| **Models** | Claude Opus 5 (copilot) |

Get-PlanIndex.ps1 wraps Get-PlanMetadata in a try/catch, appends a message to an errors list, and continues. The plan REQ/RISK/decision records are then absent from both the JSON plans array and the markdown body, the run exits 0, and the only trace is a trailing errors section. Meanwhile REQ-6 and the delivered /cip instruct the agent to reconcile against prior plans through Get-PlanIndex.ps1, not by reading the plan corpus - and neither SKILL.md nor interview-guide.md tells it to check errors or to stop when the list is non-empty. The failure mode is self-selecting: the plans that drop out are precisely those whose assets hit the resolver fail-loud paths. A plan with a broken asset layout is also the plan most likely to hold decisions someone needs to reconcile against, and the drafting interview will conclude that no prior decision exists.

**References:** REQ-6 · interview-guide.md · scripts/skalary/Get-PlanIndex.ps1

---

### [31] Get-PlanIndex.ps1 re-parses the whole corpus on every invocation and reads each plan twice, so the amortization its own header claims was never built

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | performance |
| **Models** | Claude Opus 5 (copilot) |

Get-PlanIndex.ps1 opens with the claim that parsing every plan is expensive and grows with the archive, so this script aggregates the records once into an addressable index. As delivered there is no once: no index artifact is written or cached, so every invocation walks Get-PlanInventory (which reads each plan.md raw) and then calls Get-PlanMetadata per plan, which reads the same plan.md raw a second time plus, for assets-layout plans, up to three additional asset files. The Filter is applied after the full parse, so filtering bounds the output the operator reads but not the work done. The consumption pattern multiplies this: interview-guide.md runs it at the prior-art gate and its question bank tells the interviewer to run it per topic, so one interview is topics times two times the plan count in file reads. Coverage is deliberately the whole corpus including archived, which is append-only and grows without any retention bound.

**References:** REQ-6 · steps 3.1, 3.2

---

### [32] Get-ReviewScope.ps1 is still homed under agents/scripts/ after phase 6 moved its only consumer into the skill, leaving the plugin with two script roots

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | architecture-patterns · maintainability-consistency |
| **Models** | Claude Opus 5 (copilot) |

Phase 6 moved /cr orchestration out of the agent and into the skill, and the agent is now a shim asserted not to mention Get-ReviewScope at all. The scope emitter nonetheless still installs to agents/scripts/Get-ReviewScope.ps1 and is invoked from there by scope-guide.md, while the skill other bundled script sits at skills/cr/scripts/Build-ReviewReport.ps1. The location was inherited from the deleted diff helpers, which lived there when the agent genuinely ran them; nothing moved when the ownership did. The path was also frozen into the REQ-11 evidence marker and into DiffExtractionRetired.Tests.ps1, which asserts agents/scripts/ contains exactly that one entry - so the layout is now pinned by test at the position the design moved away from. The practical consequence is namespace rather than function: .github/agents/scripts/ is a flat directory shared by every installed plugin, whereas the per-skill scripts folder is namespaced.

_Also noted:_ Step 5.1 created the emitter at plugins/code-review/agents/scripts/Get-ReviewScope.ps1 - the location that made sense while cr.agent.md owned orchestration. Step 6.3 then reduced cr.agent.md to a thin shim and moved orchestration into skills/cr/, and the script only callers are now skill assets: scope-guide.md names the agents-scripts path in every mode row. The plugin consequently ships scripts from two roots, and the second installs into a root shared across plugins rather than namespaced under the owning skill.

**References:** REQ-11 · REQ-12 · steps 5.1, 5.3, 6.1 · steps 5.1, 6.3

---

### [33] New scripts fall through the design-note glob routing to a note that does not describe them, and the index Scope column drifted from the notes own frontmatter

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | maintainability-consistency |
| **Models** | Claude Opus 5 (copilot) |

New-Epic.ps1 is documented in detail in plan-workflow.design.md but is absent from that note globs list, which enumerates plan scripts one by one and does include the sibling Get-PlanIndex.ps1. The same applies to Build-ReviewReport.ps1, Test-ModelAllowlist.ps1 and Test-SkillSize.ps1: each is described in copilot-customizations.design.md, whose globs are .github only. All four therefore match only the scripts/skalary glob in plugin-registry.design.md and route a reader to the note that documents packaging, not the note that documents the script. Separately, the Scope column for plan-workflow.design.md in the index still lists a seven-script set while the note frontmatter now names sixteen paths. The index is the always-on routing layer, so its Scope column being a stale subset defeats the purpose of having it.

**References:** REQ-15 · REQ-17 · steps 9.1, 10.4

---

### [34] Step 5 instructs the proposer to run the payload pipeline, whose outputs are denied by the Step 6 guard - the control fires on the primary happy path

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | security |
| **Models** | Claude Opus 5 (copilot) |

propose-guide.md tells the proposer that if an edit touches a plugin payload - the single most likely shape of an /si proposal - it must re-run Sync-PluginScripts, Sync-Dogfood, Build-Marketplace and Build-Registry so the catalogs are not left stale. Two of those writers emit paths the guard refuses: Build-Registry.ps1 writes registry.json at the repo root and rewrites README.md, and Build-Marketplace.ps1 writes .github/plugin/marketplace.json, which is outside .github/{skills,agents,prompts}/. None is in the allowed prefixes, and the guard sees untracked and unstaged paths, so Step 6 refuses every plugin-payload proposal that followed Step 5. The same document then closes both exits: never open the PR on a refusal, never explain a refusal away, never edit the guard to make a proposal fit. A blocking control that denies the workflow normal case, with no documented resolution, is a control that gets worked around - and the only available workaround is to skip the pipeline, which leaves registry.json carrying the pre-edit sha256 for the changed payload. That is the integrity attestation consumer installs verify against.

**References:** REQ-14 · RISK-5 · RISK-6 · steps 8.2, 10.5

---

### [35] Repair-EmptyLearningsSections re-inserts the placeholder on every overflow, and the delivered log is visibly corrupted by it

| | |
|---|---|
| **Severity** | Low |
| **Concerns** | operability-observability |
| **Models** | Claude Opus 5 (copilot) |

Repair-EmptyLearningsSections decides a section is empty by scanning for list-item lines only, so the placeholder it inserts never satisfies its own emptiness test, and each subsequent cap invocation inserts another copy into every still-empty section. assets/logs/learnings.md shows the result: eight consecutive no-entries lines under Phase 2, nine under Phase 3, seven under Phase 4, tapering with each later section - a direct readout of how many overflow events fired after each header appeared. The impact is small but it is the diagnostic artifact itself that is damaged: the file /si reads is padded with noise, the placeholder count is an accidental side channel nobody documented, and the corruption ran for ten phases in the repo own flagship plan without anyone noticing - which is itself the observability signal.

**References:** REQ-20 · step 1.6

---

### [36] The seven concern ids are restated ungated in the design note that forbids exactly that for the other dispatch constants

| | |
|---|---|
| **Severity** | Low |
| **Concerns** | maintainability-consistency |
| **Models** | Claude Opus 5 (copilot) |

copilot-customizations.design.md authors the full concern roster twice, immediately above the paragraph instructing readers not to restate the roster models or the invocation budget because a second copy is a second thing to drift. The concern ids are also authored independently in the dispatch guide table, the concern-ledger map, the agents frontmatter arrays of cr.agent.md and dr.agent.md, the agent-to-host map in tools/model-allowlist.psd1, and three separate literal lists in ConcernAgents.Tests.ps1, DispatchGuide.Tests.ps1 and DiffExtractionRetired.Tests.ps1. The executable copies cross-check each other; the design-note copy is checked only for the phrase concern roster, so dropping or renaming a concern leaves this note silently wrong.

**References:** step 10.4 (REQ-17)

---

## Recommendations

1. **[Critical] Delivered tests that prove a requirement clause are not wired to the requirement, so the receipt line under-proves the REQ** — Add a crosscheck rule that every test id under tests/ belongs to at least one REQ.
2. **[Critical] REQ-2 malformed-fails-loud is implemented as zero-records-fails-loud, so a partially malformed asset silently shrinks the requirement set** — Count rows that look like records but fail the shape test and throw on a non-zero count.
3. **[Critical] Step 10.5 mandates npm run eval, but no evidence marker covers it, so its two failures survive only in a log the run own contract calls ephemeral** — Add a dedicated eval marker requiring zero failures, or record and approve a typed deferral before phase completion.
4. **[Critical] The acceptance gate own pass condition is unreachable, and nothing in the plan closes the loop after it** — Add a mandatory post-gate crosscheck step, dependency-edged to the human gate, that re-runs the markers the gate produces and rewrites the receipt.
5. **[Critical] The dr concern tier is keyed on plan lines, and the assets split shrank that number by about 75 percent - a migrated plan now reads as the cheapest tier** — Define DR size as the combined lines or bytes of plan.md plus mandatory assets and followed decision records, and test tier selection against an assets-layout fixture.
6. **[Critical] The learnings cap destroys the entries it claims to fold, and this run lost 10 of its own 18 learnings with no recoverable trace** — Fold overflow into a dated archive file and point the summary line at it, or at minimum return the folded entry text so the caller can commit it before it disappears.
7. **[Critical] The plan-assets layout is a contract with no owner and no gate, and non-/ci writers already violate it in the delivered tree** — Make the layout a validator stage and route the autopilot transcript writer through the resolver, or downgrade the contract text to the sections /ci reads.
8. **[Critical] Two design notes shipped by this plan are absent from both discovery indexes, and the index-integrity test cannot catch it** — Add it to the exploration index.
9. **[Critical] Update-FeedbackQueue truncates operator verdicts at 300 characters with no marker, and all three of this gate recorded verdicts are cut off mid-word** — Drop the cap, or append an explicit truncated token plus a full-text sidecar and emit a Truncated property so /pfb can tell the operator their answer did not fit.
10. **[Critical] copilot-customizations.design.md still documents the pre-assets monolithic plan format and a /ci flow without the gates this plan added** — Delete the format snippet and the duplicated flow narrative, leaving a pointer to plan-workflow.design.md.
11. **[High] Shared review assets use a second duplication mechanism that contradicts the repo documented managed-duplication pattern** — Add a canonical shared-asset source generated through the payload pipeline.
12. **[High] The REQ-6 behavioural clause is proven by a bare substring, alone among its peers** — Add a consumer-side test covering the /cip skill and interview guide, requiring index invocation and rejecting direct plan-corpus reads.
13. **[High] The RISK-3 mitigation is verified nine phases after the phase that owns it, and the intent second success signal has no test of its own** — Add committed hashes or a baseline manifest for legacy and archived plans and verify those bytes remain unchanged.
14. **[High] The assets layout stated per-step saving did not land on its dominant term: requirements are still read on essentially every step, and intent is a new unconditional read** — Add a lightweight state-only parse or lazy section resolution, plus a test observing which assets are opened.
15. **[High] The plan only human gate carries a Rollback for the plan, not for the gate, and the human-step-detail check cannot tell the difference** — Replace it with exact cleanup commands for the scratch clone, branch, staged edit and generated plan, and record the implementation commit range separately.
16. **[High] The review:cr and review:dr markers carry no pass predicate, and they are the sole non-prose proof for REQ-9** — Attach a structural test over both review skills verifying delegation, explicit model dispatch, selected-concern iteration and union-once behaviour.
17. **[High] The scaffolds array extends the install-confinement boundary but was recorded only below the architecture tier** — Extend arch-install-confinement.md and its contract JSON to define first-use scaffolding, its modes, ownership and registry propagation.
18. **[High] A forward [after:] edge deadlocks step selection permanently, and nothing in the delivered validator prevents authoring one** — Add an ordering check in Test-Plan.ps1 that an after target must precede its step in document order, blocking under evidence-required plans.
19. **[High] Plan-completion harvest wrote ledger entries from phase 10 only, and nothing reports harvest coverage, so nine phases of lessons vanished silently** — Require harvest to emit a receipt - source file, entries read, entries appended per category, phases covered - and make an infra-absent skip say so out loud.
20. **[High] REQ-12 sells the skill split as CLI-usable, but the delivered dispatch contract is VS Code-only** — Add a host-resolution step to the dispatch guide, or state that /cr and /dr are VS Code-host skills and drop the unreachable CLI fallback entry.
21. **[High] Reviewer context cost is unbounded despite bounded invocation count** — Add a measured byte or token budget, a large-file policy, a maximum aggregate scope, and a reported estimated context cost.
22. **[High] Scaffold confinement does not resolve symlink escapes** — Use component-wise real-path resolution in every scaffold writer and add symlink-escape tests.
23. **[High] The /si write allowlist admits host-executed, credential-handling code under plugins/ - the executability threat model stops at .github/workflows/** — Add a second denylist tier for plugins/*/scripts/, plugins/*/devcontainer/ and plugins/*/skills/*/scripts/, or invert to a file-shape allowlist.
24. **[High] The concern-split review architecture never reached the autonomous path, which still carries a second, older taxonomy** — Point autopilot step 17 at the cr skill, or make the review-hints block reference the single concern taxonomy and name the mapping rule in the design note.
25. **[High] The dr batching contract makes the requirements asset both a batch and mandatory shared context in every other batch, so the largest asset is re-read once per batch** — State the shared context once per invocation ahead of the batches, or bound dr batch count and shared-context payload the way cr bounds files per batch.
26. **[High] The evidence-marker grammar promises a regex but the table-cell parser has no pipe escape, so alternation silently truncates the assertion** — Reject an unescaped pipe in a REQ row, or honour an escaped pipe in Split-MarkdownTableCells and the marker extractors; fix the scaffold and guides that demonstrate the trap.
27. **[High] test: markers are outside the machine-checked evidence path entirely - nothing binds a marker id to a test that exists** — Add a corpus test that parses every plan test marker and asserts each matches at least one It name under tests/.
28. **[Medium] ADR harvest bypasses the shared layout resolver** — Route Import-ArchAdr.ps1 through Resolve-PlanAssetPath and add dual-layout plus both-present tests.
29. **[Medium] Fence integrity for harvested text rests entirely on a model-generated random id; all three storage-time sanitizers pass angle brackets through** — Neutralize angle brackets or rewrite the literal UNTRUSTED_INPUT token at write time in the three sanitizers.
30. **[Medium] Get-PlanIndex degrades silently: an unparsable plan drops out of the index, exit code stays 0, and no consumer is told to read the error list** — Make a non-empty errors list a non-zero exit, or make the interview guide read errors first and fall back to the corpus for the named plans.
31. **[Medium] Get-PlanIndex.ps1 re-parses the whole corpus on every invocation and reads each plan twice, so the amortization its own header claims was never built** — Persist the built index or build it once per session and filter in memory, and reuse the raw content Get-PlanInventory already read.
32. **[Medium] Get-ReviewScope.ps1 is still homed under agents/scripts/ after phase 6 moved its only consumer into the skill, leaving the plugin with two script roots** — Re-home it to skills/cr/scripts/ with the manifest, scope guide, settings key and tests updated together, or document the exception.
33. **[Medium] New scripts fall through the design-note glob routing to a note that does not describe them, and the index Scope column drifted from the notes own frontmatter** — Add the new scripts to the owning notes globs and regenerate the index Scope cells from frontmatter.
34. **[Medium] Step 5 instructs the proposer to run the payload pipeline, whose outputs are denied by the Step 6 guard - the control fires on the primary happy path** — Allowlist the three generated catalog paths as an explicit tested exception, or run the pipeline after the guard and re-run the guard over the generated set.
35. **[Low] Repair-EmptyLearningsSections re-inserts the placeholder on every overflow, and the delivered log is visibly corrupted by it** — Guard the insertion on the placeholder already being present, and assert one placeholder per empty section after repeated cap invocations.
36. **[Low] The seven concern ids are restated ungated in the design note that forbids exactly that for the other dispatch constants** — Replace the enumeration with a pointer to the dispatch guide, or extend DesignNotes.Tests.ps1 to compare the note roster against the agent files.

---

Two things about this report itself, since the gate turns on them: the ten Critical severities are all **elevated** by the formatter's unanimity rule, not authored at Critical by any reviewer. And finding [4] applies to this run — running `/dr` does not by itself flip `review:dr` in `assets/evidence.md`; the receipt still carries both `✗` marks, so the gate's own "no `✗`" criterion cannot be met without a step the plan does not declare.

The full report is at `%TEMP%\dr-b0c0d3-report.md`. Gate 1 preserved its report at `assets/reviews/gate-10.7-cr-branch.md`; I can write this one to `assets/reviews/gate-10.7-dr-plan.md` as the `review:dr` evidence for REQ-9 if you want the same treatment.

Which findings do you want to act on — a number, a range (e.g. 1–10), or `all`? Or use the **Update plan** handoff to revise the plan in plan mode.