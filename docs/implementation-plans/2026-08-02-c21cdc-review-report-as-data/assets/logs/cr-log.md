## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] New-layout summary/full byte goldens were missing; expectation-only fixtures could not pin rendered bytes or bounds.
- [1.1] [src:code-review] [sev:Med] Maximum-envelope fixture created 256 merged groups, exceeding the schema-owned 128-group semantic limit.
- [1.1] [src:code-review] [sev:Med] Manifest artifact-name schema allowed 100 characters while the shared vocabulary declared a 96-character maximum.
- [1.1] [src:code-review] [sev:Med] Reference merge keys were computed before NFC normalization, splitting canonically equivalent findings.
- [1.1] [src:code-review] [sev:Med] Case-insensitive PowerShell roster membership could falsely elevate findings from case-distinct declared models.
- [1.1] [src:code-review] [sev:Med] Terminal-status schema allowed degraded exit 5 in Freeze mode even though degradation is Publish-only.
- [1.1] [src:code-review] [sev:Med] Maximum-envelope fixture omitted maximum diagnostics and therefore did not exercise the largest semantically valid near-cap record mix.
- [1.1] [src:code-review] [sev:Med] Reference raw-record lookup used a case-insensitive delimiter key that could overwrite distinct legal findings.
- [1.1] [src:code-review] [sev:Med] Schema capability preflight could ignore unlisted assertion keywords and count validator exceptions as successful negative probes.
