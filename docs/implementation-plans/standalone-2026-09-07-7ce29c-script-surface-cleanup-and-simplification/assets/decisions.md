# Decisions

- Perform the full architecture human-document compatibility cleanup; Markdown architecture notes
  remain authoritative and the remaining JSON contract keeps direct validation only.
- Keep `clean-sandbox-cache.ps1` as an explicit operator maintenance utility despite having no runtime
  caller.
- Delete the completed prefix migration instead of repairing its current archived-epic preflight failure.
- Replace historical implementation snapshots with current-state absence evidence; Git history owns
  historical bytes.
- Simplify the three large active modules through evidence-led in-place deletion.
- Preserve each module's exact public exports and supported behavior.
- Require a net decrease in private functions and token-bearing source lines for every module, without
  an arbitrary percentage target.
- Do not create production modules to move complexity out of the measured files.
- Use current focused tests and one final risk-selected CR; do not add a broad routine validation path.
