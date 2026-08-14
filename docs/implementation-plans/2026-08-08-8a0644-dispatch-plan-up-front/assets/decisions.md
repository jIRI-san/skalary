# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **One shared fleet scheduler.** `/cip`, `/ci`, `/cr`, `/dr`, and `/cep` coherency review use the same admission, wave, attendance, and throttling contract.
- **Cap concurrency at four invocations.** The cap limits in-flight provider load, not selected coverage; larger fleets run in declared waves.
- **Declare the run before dispatch.** The plan lists selected roles or concern/model pairs, total invocations, omissions, cap, wave order, and retry policy before calls begin.
- **Never hide omissions.** Work dropped by scope or budget is named with a reason; throttling cannot silently convert a full run into partial attendance.
- **Preserve independent passes.** Reading batches do not multiply concern passes, and selected concern/model pairs still run independently once.
- **Bound retries, then report degradation.** Rejected: replacement calls or unlimited retries that obscure what actually ran.
