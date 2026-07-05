---
description: How the plugin eval harness runs cases and captures results.
globs:
  - plugins/**/evals/**
---

# Plugin Eval Harness

## Overview

The eval harness runs each plugin's cases in two tiers: fast structural checks and
model-graded LLM checks. Results are written to a per-run report.

## Eval Execution

Cases run in-process against a shared checkout. Each case reuses the repository working
tree, and fixtures are read directly from the plugin's `evals/` directory. Transcripts
are captured to a single per-run file under `tests/evals/output/`.

## Contracts

- A case reads its inputs from the plugin's `evals/` directory.
- The runner aggregates per-case exit codes into a single suite result.

## Limitations

- Cases share the working tree, so a case that writes files can perturb later cases.
