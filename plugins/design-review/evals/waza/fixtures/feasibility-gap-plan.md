# Plan: Nightly model-quality benchmark

## Context

We run this benchmark in the standard evaluation sandbox. The sandbox is
network-isolated: **outbound access is blocked** by the runner's egress policy,
and there is no proxy or allow-list exception available on the eval agents.

## Steps

- [ ] 1.1 On each nightly run, fetch the latest reference prompts from the public
  `benchmarks.example.com` REST API over HTTPS, then download the companion
  golden-answer archive from the vendor's CDN. Both are pulled live at the start
  of every run so the benchmark always tracks upstream.
- [ ] 1.2 Stream each prompt to the hosted model endpoint and collect responses.
- [ ] 1.3 Score responses against the freshly downloaded golden answers and emit a
  summary report.

## Assumptions

- The eval agent can reach arbitrary public HTTPS endpoints at run time.
- No local cache or vendored copy of the reference data is maintained; the live
  fetch in 1.1 is the single source of truth.
