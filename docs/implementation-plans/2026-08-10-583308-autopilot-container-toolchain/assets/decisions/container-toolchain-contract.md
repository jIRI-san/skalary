# Container toolchain contract

## Acquisition boundary

`plugins/autopilot/devcontainer/toolchain.tsv` is the sole executable inventory for the additional agent baseline. Each non-comment line contains a unique stable case ID, one Debian package, and one conventional command. The pre-existing bootstrap packages (`git`, `curl`, `jq`, `ca-certificates`, `gnupg`, `nodejs`, `npm`) remain a separately named literal set and are excluded from baseline equality. The Dockerfile copies `toolchain.tsv` before the first apt layer and installs bootstrap plus the manifest-derived package column; it does not mirror a second baseline literal.

Before installation, reject any enabled apt source whose URI host is not `deb.debian.org` or `security.debian.org`; the structural test includes an injected-repository negative fixture. During installation, capture `/etc/os-release`, exact package versions, selected origins, and installed dependency closure before apt metadata is removed. The image retains the existing floating `.NET 10` base and Debian package policy, so this is bounded acquisition rather than byte reproducibility.

## Closed baseline

| Case ID | Capability | Debian package | Conventional command | Functional assertion as `autopilot` |
|---|---|---|---|---|
| `rg-search` | Text search | `ripgrep` | `rg` | Finds a known token recursively. |
| `fd-find` | File discovery | `fd-find` | `fd` | Finds a known filename through the root-owned alias. |
| `bat-render` | File rendering | `bat` | `bat` | `--plain` emits known content through the root-owned alias. |
| `tree-list` | Tree navigation | `tree` | `tree` | Lists a fixture directory. |
| `less-version` | Paging | `less` | `less` | Reports a version non-interactively. |
| `file-type` | File typing | `file` | `file` | Classifies a known text file. |
| `zip-create` | Zip creation | `zip` | `zip` | Creates a fixture archive. |
| `unzip-extract` | Zip extraction | `unzip` | `unzip` | Extracts and verifies the fixture archive. |
| `rsync-copy` | File synchronization | `rsync` | `rsync` | Copies a fixture tree and preserves content. |
| `native-build` | Native build | `build-essential` | `cc` | Compiles and executes a minimal C program. |
| `python-run` | Python helpers | `python3` | `python3` | Runs a minimal script. |
| `python-venv` | Isolated Python environment | `python3-venv` | `python3` | Creates an environment without network access. |
| `python-pip` | Python package client | `python3-pip` | `python3` | Reports pip version without installing a package. |
| `shellcheck-valid` | Shell lint | `shellcheck` | `shellcheck` | Accepts a valid fixture script. |
| `process-self` | Process inspection | `procps` | `ps` | Reports the current process. |
| `lsof-open` | Open-file inspection | `lsof` | `lsof` | Reports a deliberately opened fixture file. |
| `ip-loopback` | Network inspection | `iproute2` | `ip` | Reports loopback-link metadata. |
| `dig-version` | DNS diagnostics | `dnsutils` | `dig` | Reports a version without external DNS. |
| `nc-help` | TCP diagnostics | `netcat-openbsd` | `nc` | Reports help behavior without opening a listener. |
| `ssh-version` | SSH client | `openssh-client` | `ssh` | Reports a version without connecting. |
| `sqlite-query` | Local structured query | `sqlite3` | `sqlite3` | Executes an in-memory scalar query. |

The smoke script labels each implementation with `CASE:<id>`. Ordinary Pester requires exact equality among table IDs, `toolchain.tsv`, and smoke IDs and includes removed-package and removed-case mutations. The smoke also verifies that it runs as `autopilot`; `/usr/local/bin/fd` targets `/usr/bin/fdfind`; `/usr/local/bin/bat` targets `/usr/bin/batcat`; both links are root-owned; and `/usr/local/bin` is not writable by `autopilot`.

Smoke stdout is one JSON object of at most 64 KiB conforming to `skalary/container-toolchain-smoke@1`. Values are single-line, control-character-free, length-bounded, and from closed fields. The runner validates the object before rendering any value through one Markdown encoder. Raw candidate output is never written to `$GITHUB_OUTPUT`, `$GITHUB_ENV`, workflow commands, or the job summary.

## Comparable size run

`scripts/skalary/Invoke-ContainerToolchainGate.ps1` is the sole comparison implementation used locally and by Actions. Event identity is closed:

| Event | Candidate | Base |
|---|---|---|
| `pull_request` | `github.sha` synthetic merge commit | `github.event.pull_request.base.sha` |
| push to `main` | `github.sha` | `github.event.before` |

Both values enter scripts only through environment variables, must be lowercase or uppercase 40-hex, and must equal checkout `HEAD`. Detection and builds use the same pair. Changed paths are read NUL-delimited and compared as exact ordinal strings; tests cover whitespace, newlines, quotes, substitutions, leading dashes, renames, and deletions.

Control-plane code is trusted independently from candidate content. On pull requests, the workflow checks out and executes the runner from the validated base SHA in a credential-free control directory. On pushes to `main`, the candidate SHA is already trusted merged `main` and owns the runner. Candidate checkout scripts are never invoked directly on the Actions host and candidate containers receive no GitHub command-file environment variables.

For each run:

1. Verify candidate checkout identity and manifest-driven canonical/installed byte/hash parity. Candidate parity, build, and smoke are always blocking.
2. Detection with an all-zero, unreachable, or otherwise unusable base returns `relevant=true`, never false or error. Classify comparison as `comparable` or one closed candidate-only reason: `zero-base`, `base-unreachable`, `base-context-absent`, `base-payload-drift`, `base-build-failed`, or `base-timeout`. Never substitute another base. Candidate-only receipts contain absolute candidate size and no delta.
3. Pull `mcr.microsoft.com/dotnet/sdk:10.0` once; record the resolved image ID/digest and runner architecture; do not pull again during either build.
4. Resolve one Copilot CLI version and pass the same explicit build argument to both builds. Use the same daemon, platform (`linux/amd64`), and remaining build arguments.
5. Build and smoke candidate first under a 25-minute process-tree-killing budget. Only after candidate success, build comparable base under at most 10 residual minutes. Base failure or timeout converts to candidate-only evidence; it cannot consume candidate budget. Use local BuildKit cache only; publish no cache or image.
6. Enforce a 35-minute runner budget inside a 45-minute image job, and record stage elapsed times.
7. From a `finally` path, write `skalary/container-toolchain-receipt@1` for every closed outcome: `success`, `irrelevant`, `candidate-build-failed`, `candidate-smoke-failed`, `candidate-output-invalid`, `candidate-timeout`, `base-build-failed`, `base-timeout`, or `unexpected-error`. Receipt fields are fixed, bounded, and include encoded smoke summary when available, identities, provenance digest, timing, and comparison state. More than 250 MiB growth is advisory; malformed measurement or candidate failure is blocking.

The receipt and deterministic provenance file are uploaded under `if: always()` for 14 days. The internal 35-minute limit reserves ten minutes before the 45-minute job timeout for finalization/upload. If the hosted runner itself is killed before upload, the final gate records the image job's `timed_out`/non-success conclusion and missing artifact as the durable Actions diagnosis. The summary links artifact SHA-256 digest when present. If a comparable receipt exceeds 250 MiB, finalization requires `assets/decisions/image-size-exception.md`; otherwise that file is absent.

## Always-reported gate

The workflow itself triggers on every pull request and `main` push. A detector computes whether the closed image-input set changed. The image job is conditional; the final `autopilot container / gate` job uses `if: always()` and this truth table:

- detector result other than `success`, or relevance outside `true|false`: fail;
- relevance `false` plus image `skipped`: pass as no-op;
- relevance `true` plus image `success`: pass;
- every other pair: fail.

The workflow is secretless for candidate execution: no repository/organization secret, token-bearing build argument, persisted checkout credential, host Docker-socket/workspace mount into candidate containers, privilege, device, added capability, or host networking. Building uses the hosted runner daemon, but the built/running image cannot access its socket.

The trusted runner is the sole path-set owner. It derives canonical/installed mappings from `plugin.json`, parses Dockerfile `COPY` sources, and adds itself, the workflow, launcher, manifest, and owning tests. Detector and Pester call the same function; documentation names categories only.

## Accepted capability

`pip`, SSH, netcat, and DNS clients improve code retrieval and diagnostics. Their presence is accepted because the runtime already has `curl`, npm, Git, GitHub credentials, unrestricted outbound networking, and host Docker-socket authority. This plan adds no daemon, listener, capability, root execution, secret source, or command-approval bypass. Smoke checks are offline where practical and never contact an operator-controlled endpoint.

## Gate recovery

The stable check display name is `autopilot container / gate`. This plan creates the check but does not mutate branch protection. If an operator later makes it required and a detector defect or upstream outage blocks its own repair, a repository administrator may temporarily remove only this check from required status, record the incident, merge a separately reviewed repair, restore the requirement, and verify one irrelevant no-op run plus one relevant image run. The disabled interval and restoration evidence remain visible in the incident/PR record.
