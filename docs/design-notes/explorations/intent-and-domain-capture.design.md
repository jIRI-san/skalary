---
description: Deferred exploration — capturing operator intent and problem-domain knowledge well enough that an agent implementing independently understands the real goal. Covers intent provenance in intent.md, active rephrase-and-confirm interviewing, and domain modelling. Load before changing /cip or /cep interview behaviour or the intent asset.
globs:
  - plugins/create-implementation-plan/**
  - plugins/continue-implementation/**
  - docs/implementation-plans/**
---

# Intent and Domain Capture

Operator notes captured 2026-07-31 during `b0c0d3` execution. Three linked problems; the operator explicitly tied domain modelling to intent capture. **Partially resolved 2026-08-14:** `/cep` now preserves accepted epic discussion, preliminary child intent, decomposition decisions, rejected alternatives, and uncertainty in each scaffolded child's assets. Full `/cip` per-point provenance and domain modelling remain open.

## The shared failure

Plans are heavy on implementation detail and light on *desired outcome*. An agent executing independently can satisfy every step and still miss the point, because the prose that carried the point never made it into the plan. `b0c0d3` REQ-4 adds `assets/intent.md`, but only as a static artifact — nothing yet governs how its content is *elicited* or how faithfully it reflects what the operator meant.

## 1. Intent provenance in `intent.md`

Record the operator's own input on important points, sanitized and rephrased for brevity and intent, alongside the derived requirements.

Rationale: a requirement is a lossy compression of what the operator said. When an agent later hits an ambiguity, the derived requirement cannot disambiguate itself — the original phrasing often can. Today that phrasing exists only in a chat transcript that no future agent reads.

Open questions:

| Question | Why it matters |
|---|---|
| Sanitized how? | Same untrusted-input concern as `/si` (RISK-10) — operator prose is not executable instruction |
| Verbatim quote, or rephrased summary? | Rephrasing loses nuance; verbatim bloats the asset and may carry noise |
| Which points qualify as "important"? | Without a rule this becomes either everything or nothing |
| Relationship to `capture.md` | `Add-WorkflowNote -Kind Capture` already records interview decisions; overlap needs resolving, not duplicating |

## 2. Rephrase-and-confirm interviewing

Skills must play back their understanding to the operator and iterate until there is no doubt the real goal is captured — not merely ask questions and record answers.

The current `/cip` interview asks a question bank and accepts answers at face value. It confirms a *summary* once, at the end. The proposal is stronger: active extraction of meaning from vague English prose, with explicit restatement and correction cycles on each important point, gated so drafting cannot begin while understanding is uncertain.

This is a behavioural contract, so it needs an enforcement story — an unenforced "ask until certain" instruction is the assert-without-enforce pattern this repo keeps hitting. Candidate: a gate that requires a recorded operator confirmation token per important point before the `pre-draft` gate passes.

## 3. Domain modelling

Every problem domain carries specific lingo, unstated assumptions, hidden variables, and subtle meanings. Agents implementing independently need these captured or they will silently substitute generic assumptions.

Wanted: a way to capture the domain when starting on a new problem, and to keep it current as understanding evolves.

**Explicitly flagged by the operator as needing discussion before design.** Open dimensions:

| Dimension | Tension |
|---|---|
| Where it lives | Per-plan asset (dies with the plan) vs repo-level tier (persists, risks staleness) |
| Relationship to design notes | Design notes cover *this project's decisions*; domain knowledge covers *the problem space* — adjacent but not the same tier |
| How it stays current | The maintenance-protocol model (update as part of the change) vs harvest-on-completion |
| Who authors it | Elicited from the operator during interview vs derived by the agent and confirmed |

## Interaction with shipped work

`b0c0d3` delivers `assets/intent.md` (REQ-4) and the `intent` gate. That is the substrate these three build on — none of them require undoing it, and all three extend it rather than replacing it.

The `/cep` `child-context` gate now closes the epic-scaffold variant of the provenance gap: accepted context
is copied into child `intent.md`, `decisions.md`, and `references.md` immediately, and `/cip` must preserve
and refine it. This does not settle verbatim-versus-summary provenance for every `/cip` interview point,
confirmation-token enforcement, or the repository-level domain-knowledge tier.
