# Unattended execution decisions

## 1.1: Preserve replacement slots without an availability retry

- Choice: retain existing `Fallback` keys and aliases; instruction consumers refuse equal-binding
  availability retries. No new model resolver or availability service.
- Rationale: current launchers resolve one configured alias and do not implement automatic fallback;
  six Sol bindings eliminate cross-model availability replacement.
- Consequence: existing configuration/API shape and bounded context-replacement budgets stay intact.
  Unavailable Sol is a visible stop; separate review contexts are not model diversity.

## 1.2: Keep unrelated Waza inventory failures out of the model migration

- Choice: leave two pre-existing `tests/evals/WazaCreditPolicy.Tests.ps1` failures unchanged.
- Rationale: confirmed baseline `e3099c88` already contains 28 tasks while the test expects 26,
  and a factory-loop `judge_model` with deterministic-only tasks. Model sync changes only identifiers,
  not task count, grader disposition or judge-field presence.
- Consequence: model acceptance uses the four named ModelAllowlist tests plus all 10 affected Waza
  convention fixtures, runtime/model and skill-contract regressions (161 passing tests).
  The wider credit-policy file remains non-clean; no whole-repository clean result is claimed.
