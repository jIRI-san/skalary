# Plan: Self-healing eval harness

## Context

The harness asks the model to propose a fix when an eval fails, then applies the
fix automatically so the next run can proceed without human intervention.

## Steps

- [ ] 1.1 When a task fails, prompt the model to return a remediation command as a
  plain string (for example, a shell one-liner that patches the fixture or resets
  state).
- [ ] 1.2 Take the model's returned string verbatim and run it through the system
  shell (`bash -c "$modelOutput"`) inside the eval workspace to apply the fix.
- [ ] 1.3 Re-run the task and record whether the self-heal succeeded.
- [ ] 1.4 Repeat up to three times per task.

## Assumptions

- The model's output is trusted to be a well-formed, safe command.
- No validation, allow-listing, or sandboxing is applied to the returned string
  before it is executed — the string IS the command.
