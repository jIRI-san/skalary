# Cross-repository handoff

Consumer-installed customizations are distribution copies, never upstream source. For an
upstream-worthy consumer learning:

1. Finish normal consumer `/si` ranking and disposition recording so the durable SI run cites the
   ledger, capture, and SI activity that produced each candidate.
2. Invoke installed `Export-CrossRepoSi.ps1` with that run, the installed plugin version, and the
   single `docs/self-improvement/cross-repo-export.json` output. The writer redacts known credential
   forms, fences candidate text, rejects oversized input before writing, and makes replay
   content-addressed and byte-stable.
3. Open a clean checkout of the customization's upstream repository as a new workspace root. Invoke
   installed `Invoke-CrossRepoSiHandoff.ps1` from that checkout. It refuses dirty or nested
   checkouts, loads and digests the upstream repository instructions, validates the artifact, and
   returns a fresh untrusted-input fence.
4. Pass only the returned fenced `Context` to the returned `Action`: `/si` for `Small` work or `/cip`
   for `PlanSized` work. Re-judge every consumer claim against current upstream code and rules.

The handoff grants no publication authority. Normal upstream `/si` retains
`Test-SiWriteScope.ps1`, draft-only PRs, and never-auto-merge. `/cip` produces a normal reviewed
implementation plan; it does not bypass those controls.
