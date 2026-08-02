# Intent

> Captured in the `/cip` interview on 2026-08-02 and confirmed by the operator. Supersedes the
> agent-proposed draft written while the operator was unavailable.

## Goal

We have a fast enough feedback loop in tests so we can iterate quickly, we are confident that the gates
are validating what was developed, and that the results make sure we are not breaking things or
introducing bugs.

## Desired outcome

The gates the repo already claims to have become real, and cheap. The full unit suite and
`validate.ps1` run on every PR on both platforms; the test command fails when it cannot test; generated
catalogs are byte-identical regardless of the contributor's locale; `validate.ps1` parses the same file
set on Windows and Linux; the validator can tell a scaffolded plan from a broken one; and constants the
repo asserts in prose are pinned to the gated source. The suite finishes in minutes, not half an hour,
so running it is never the expensive option.

## Success signals

- `npm test` finishes under 5 minutes; 10 minutes is the outer bound.
- Reverting any fix from this epic turns a PR red.
- A freshly scaffolded plan passes validation; a drafted plan with a genuinely invalid marker still fails.
- `Run-UnitTests.ps1` exits non-zero when Pester is absent instead of reporting success.
- `registry.json`, `marketplace.json` and `README.md` built under `cs-CZ` are byte-identical to the same
  files built under `en-US`.
- `validate.ps1` parses the same file count on Windows and Linux.
- Coverage is not reduced: the assertions that exist today still run.

## Non-goals

- The evidence receipt's inability to express `skipped` — that is `863d97`, and duplicating it here
  would fork that child's contract.
- The review report's attendance and size problems — that is `c21cdc`.
- Adding new gates. This plan makes existing gates real and affordable; a genuinely new control belongs
  elsewhere.
- Moving the LLM eval tier into CI. Plan `005` excluded it deliberately (REQ-12, RISK-3); nothing here
  disturbs that.
- Changing what the tests assert. Redundancy is removed; coverage is not.

## Definition of done

Operator's bar: tests running under 10 minutes and ideally 5, some redundancies removed, and increased
confidence in the results. Concretely — every gate the repo advertises either runs on every PR or is
recorded as a deliberate exclusion, and no gate can pass by silently executing nothing.
