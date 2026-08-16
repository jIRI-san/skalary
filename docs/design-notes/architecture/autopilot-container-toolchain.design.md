---
description: Durable contract for the autopilot execution image's agent baseline, its smoke program, the trusted-host attestation of what the image actually contains, and the post-merge comparison gate that measures it. Load before editing plugins/autopilot/devcontainer/**, scripts/skalary/Invoke-ContainerToolchainGate.ps1, or .github/workflows/autopilot-container-ci.yml.
globs:
  - plugins/autopilot/devcontainer/**
  - .github/skills/autopilot/devcontainer/**
  - scripts/skalary/Invoke-ContainerToolchainGate.ps1
  - .github/workflows/autopilot-container-ci.yml
  - tests/skalary/AutopilotContainer*.Tests.ps1
---

# Autopilot container toolchain

Durable contract for the autopilot execution image's agent baseline, its smoke program, and the
comparison gate that measures it. This note is the source of truth the structural tests read.
It lives here rather than in a plan folder because plan folders are archived on completion, and a
contract that disappears from its enforcing test's path is a contract that stops being enforced.

**Applies to:** `plugins/autopilot/devcontainer/**`,
`scripts/skalary/Invoke-ContainerToolchainGate.ps1`,
`.github/workflows/autopilot-container-ci.yml`, `tests/skalary/AutopilotContainer*.Tests.ps1`

## Acquisition boundary

`plugins/autopilot/devcontainer/toolchain.tsv` is the sole executable inventory for the additional
agent baseline. Each non-comment line contains a unique stable case ID, one Debian package, and one
conventional command. The pre-existing bootstrap packages (`git`, `curl`, `jq`, `ca-certificates`,
`gnupg`, `nodejs`, `npm`) remain a separately named literal set and are excluded from baseline
equality. The Dockerfile copies `toolchain.tsv` before the first apt layer and installs bootstrap
plus the manifest-derived package column; it does not mirror a second baseline literal.

Before installation, reject any enabled apt source whose URI host is not `deb.debian.org` or
`security.debian.org`; the structural test includes an injected-repository negative fixture. During
installation, capture `/etc/os-release`, exact package versions, selected origins, and installed
dependency closure before apt metadata is removed. The image retains the floating `debian:trixie-slim`
base and Debian package policy, so this is bounded acquisition rather than byte reproducibility.

Artifacts fetched over the network and then installed with root trust are bound to a digest or key
fingerprint recorded in the Dockerfile: the Microsoft package-repository `.deb`, the pinned GitHub
CLI `.deb`, and the Docker apt signing key. A rotated upstream artifact fails the build closed. That
is deliberate: an unpinned root install is a supply-chain hole, and a build that stops because
Microsoft republished its configuration package is a maintenance task, not a security incident.

The Docker key is pinned by construction, not by inspection. The fetched armored file is imported into
a throwaway `GNUPGHOME`, and only the pinned fingerprint is exported into the keyring named by
`signed-by=`, which is then asserted to hold exactly one primary key. Dearmoring the fetched file whole
and checking that the expected fingerprint appears in it would accept a file carrying the genuine
Docker key *and* an attacker's, and apt would trust both.

## Provenance describes the shipped image

The Debian baseline provenance capture runs inside the first apt layer, so on its own it describes
an image that does not exist yet — PowerShell, .NET, GitHub CLI, Docker CLI and npm globals all land
later. A final root-layer capture therefore runs as the last root layer — after the last root install *and*
after the non-root user is created, immediately before `USER autopilot` — recording
`final-apt-sources.txt`, `final-packages.tsv`, and `final-npm-globals.json`. The ordering is not
cosmetic: `# Non-root user` is the documented anchor for extending the image, so a capture placed
above it would omit whatever a later maintainer adds there, reproducing at the anchor exactly the gap
the baseline capture already demonstrated. The smoke program reports `origin.aptHosts` from the final file, and the
gate's attestation reads the same file from the image. The allowed origin set at final state is
`deb.debian.org`, `security.debian.org`, `download.docker.com`, and `packages.microsoft.com`; the
Debian baseline file may still only contain the first two.

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
| `dig-version` | DNS diagnostics | `bind9-dnsutils` | `dig` | Reports a version without external DNS. |
| `nc-help` | TCP diagnostics | `netcat-openbsd` | `nc` | Reports help behavior without opening a listener. |
| `ssh-version` | SSH client | `openssh-client` | `ssh` | Reports a version without connecting. |
| `sqlite-query` | Local structured query | `sqlite3` | `sqlite3` | Executes an in-memory scalar query. |

The smoke script labels each implementation with `CASE:<id>`. Ordinary Pester requires exact equality
among table IDs, `toolchain.tsv`, and smoke IDs and includes removed-package and removed-case
mutations. The smoke also verifies that it runs as `autopilot`; `/usr/local/bin/fd` targets
`/usr/bin/fdfind`; `/usr/local/bin/bat` targets `/usr/bin/batcat`; both links are root-owned; and
`/usr/local/bin` is not writable by `autopilot`.

Smoke stdout is one JSON object of at most 64 KiB conforming to `skalary/container-toolchain-smoke@1`.
Values are single-line, control-character-free, length-bounded, and from closed fields. The runner
validates the object before rendering any value through one Markdown encoder. Raw candidate output is
never written to `$GITHUB_OUTPUT`, `$GITHUB_ENV`, workflow commands, or the job summary.

## Smoke claims are attested, not believed

The smoke program runs inside the candidate image and reports its own manifest digest and origins, so
on its own it can only state what the candidate wants stated. After a claimed pass, the runner reads
the image from the trusted host — `docker create --network none` plus `docker cp` — and compares:

- the copied `/usr/local/share/autopilot/toolchain.tsv` digest against the trusted checkout's manifest;
- the copied Debian baseline sources against the two-host Debian allowlist;
- the copied final sources against the four-host final allowlist;
- the image's live `/etc/apt` tree — every `sources.list`, `*.list` and `*.sources` file, comments
  skipped and keyrings not read — against the same final allowlist, and it must name at least one host.
  The compared token is the whole URI authority minus any port, exactly as the recorded-file reader
  produces it, so `https://download.docker.com@evil.example.com/…` — which apt resolves against
  `evil.example.com` — cannot read as an allowed host in one reader and a rejected one in the other.
  A non-`http(s)` scheme is reported as `<scheme>://<authority>` rather than skipped, so an `ftp:` or
  `mirror+file:` origin fails the allowlist instead of being invisible to a pattern that only knows
  how to see http. `apt.conf` and `apt.conf.d/*` are scanned too, and a `Dir` root reassignment or any
  `Dir::Etc*` directive fails the read closed: those relocate the source-list directory both readers
  enumerate, so an allowlisted `/etc/apt` that apt never consults would otherwise pass. `Dir::Cache*`
  is not included, because Debian's own base images ship it and it relocates no source list. Any
  enumeration or read error fails the read closed rather than reporting the hosts it managed to read;
- the smoke object's `digests.manifestSha256` and `origin.aptHosts` against those attested values.

Disagreement is `candidate-output-invalid`. No candidate code runs on the host in this path: `docker cp`
extracts files, and no mount, socket, or elevated flag is involved. The whole attestation shares one
deadline rather than giving each `docker cp` its own, so it cannot outlive the budget it was handed;
exhausting it is the closed reason `attestation-timeout`.

What this establishes is bounded, and the bound matters. The manifest digest is compared against the
trusted checkout, so that comparison has a trusted side. The provenance files do not: they are written
by the candidate's own Dockerfile, so a Dockerfile that installs from an unlisted host and then writes
a clean record — and a matching `/etc/apt` — still passes. Reading the live configuration raises the
cost of that lie from one file to a consistent forgery across the image, and cross-checking smoke
against both catches a lying smoke program outright, but neither turns a candidate-authored record into
independent provenance. The hostile *build recipe* is caught by human review of the diff, which is
exactly what the Dockerfile's visibility in the pull request is for. The gate detects an image that
contradicts itself; it does not certify one that lies consistently.

A smoke payload with no cases is rejected outright. An emptied manifest would otherwise render
`0 cases; state=pass` — a green run that exercised nothing, which is the one verdict this gate must
never report.

When smoke reports failures, the receipt and job summary name the failing case IDs (bounded to 32),
because a bare count tells a reader nothing they can act on.

Not every smoke failure belongs to a case. Nine whole-run conditions — running as the wrong user, a
writable `/usr/local/bin`, an unreadable or duplicate-keyed manifest, a case-count mismatch, missing
provenance files, a digest that could not be computed, an encoder failure — used to collapse into a
bare `state=fail`, and the receipt could then say only "reported failure without naming a case".
`skalary/container-toolchain-smoke@1` therefore carries a required `reasons` array drawn from a closed
vocabulary: `case-count-mismatch`, `encoder-failed`, `manifest-digest-unavailable`,
`manifest-duplicate-case`, `manifest-unreadable`, `not-autopilot-user`, `output-oversize`,
`provenance-digest-unavailable`, `provenance-incomplete`, `usr-local-bin-writable`. The vocabulary is
closed so a broken or hostile image cannot use the field as a free-text channel into the job summary. It is empty on `pass`, and a `fail`
with neither a failing case nor a reason is rejected as invalid output — a verdict with no diagnosis is
not a verdict. The schema version is not bumped because the schema has never shipped outside this
branch; the field is required from its first release.

## Comparable size run

`scripts/skalary/Invoke-ContainerToolchainGate.ps1` is the sole comparison implementation used locally
and by Actions. The gate runs on one event, and event identity is closed:

| Event | Candidate | Base |
|---|---|---|
| push to `main` | `github.sha` | `github.event.before` |

Both values enter scripts only through environment variables, must be lowercase or uppercase 40-hex,
and must equal checkout `HEAD`. Detection and builds use the same pair. Changed paths are read
NUL-delimited and compared as exact ordinal strings; tests cover whitespace, newlines, quotes,
substitutions, leading dashes, renames, and deletions.

Both checkouts are `fetch-depth: 1`. The runner needs the base *commit object* in the candidate
clone to diff two trees, which a full-history clone used to supply at the cost of transferring the
entire repository twice per push; instead the base commit is fetched from the base checkout already
on disk (`git -C candidate fetch --no-tags --depth=1 <base-root> <base-sha>`), which needs neither
network nor credentials and so keeps working for a private repository with `persist-credentials:
false`. If that import fails, the runner cannot resolve the base and closes to `base-unreachable`,
which forces relevance and a blocking candidate-only measurement.

There is one checkout of trusted code, and it is the merged commit. Candidate checkout scripts are
never invoked directly on the Actions host and candidate containers receive no GitHub command-file
environment variables — only the runner from the merged commit executes on the host.

For each run:

1. Verify candidate checkout identity and manifest-driven canonical/installed byte/hash parity.
   Candidate parity, build, smoke, and attestation are always blocking. A parity failure writes the
   partial hash entries it computed into provenance and names the offending path in the receipt,
   because "payload parity failed" without a path is not a diagnosis.
2. Detection with an all-zero, unreachable, or otherwise unusable base returns `relevant=true`, never
   false or error. Classify comparison as `comparable` or one closed candidate-only reason:
   `zero-base`, `base-unreachable`, `base-context-absent`, `base-payload-drift`, `base-build-failed`,
   or `base-timeout`. Never substitute another base. Candidate-only receipts contain absolute
   candidate size and no delta.
3. Measurement receives the detector's relevance verdict. If measurement re-derives irrelevance while
   the detector said `true`, the contradiction resolves toward the blocking path and is recorded in the
   receipt diagnostic; the truth table never sees `detector=true` with an unbuilt candidate.
4. Pull `debian:trixie-slim` once; record the resolved image ID/digest and runner architecture; do not
   pull again during either build. Install the maintained .NET 10 SDK only after the Debian baseline
   layer, from Microsoft's Debian 13 repository.
5. Resolve one Copilot CLI version and pass the same explicit build argument to both builds. Use the
   same daemon, platform (`linux/amd64`), and remaining build arguments.
6. Build and smoke candidate first under a 25-minute process-tree-killing budget. Only after candidate
   success, build comparable base under at most 10 residual minutes. Base failure or timeout converts
   to candidate-only evidence; it cannot consume candidate budget. Use local BuildKit cache only;
   publish no cache or image.
7. Enforce a 35-minute runner budget inside a 45-minute image job, and record stage elapsed times.
8. From a `finally` path, write `skalary/container-toolchain-receipt@1` for every closed outcome:
   `success`, `irrelevant`, `candidate-build-failed`, `candidate-smoke-failed`,
   `candidate-output-invalid`, `candidate-timeout`, `base-build-failed`, `base-timeout`, or
   `unexpected-error`. Receipt fields are fixed and bounded and include the encoded smoke summary and
   failed case IDs when available, identities, provenance digest, timing, and comparison state.
   More than 250 MiB growth is advisory; malformed measurement or candidate failure is blocking.

Process output is captured head-and-tail with an explicit truncation marker, because a Docker build
failure is announced in its last lines and a head-only capture reliably discards it. Receipt
diagnostics carry a bounded tail; the full bounded capture for a failing stage is written to the
diagnostics log and uploaded with the other evidence.

The receipt, provenance file, summary, and diagnostics log are uploaded under `if: always()` for 14
days. The internal 35-minute limit reserves ten minutes before the 45-minute job timeout for
finalization/upload. If the hosted runner itself is killed before upload, the final gate records the
image job's `timed_out`/non-success conclusion and missing artifact as the durable Actions diagnosis.
The job summary states outcome, blocking state, comparison, both image sizes, the delta against the
advisory threshold, stage timings, smoke result with any failed cases, and the diagnostic — a summary
that omits the numbers forces a reader into the artifact for the one fact the summary exists to give.
If a comparable receipt exceeds 250 MiB, finalization requires `assets/decisions/image-size-exception.md`;
otherwise that file is absent.

## Post-merge gate

The workflow triggers on `push` to `main` and on nothing else. A detector computes whether the closed
image-input set changed. The image job is conditional; the final `autopilot container / gate` job uses
`if: always()` and this truth table:

- detector result other than `success`, or relevance outside `true|false`: fail;
- relevance `false` plus image `skipped`: pass as no-op;
- relevance `true` plus image `success`: pass;
- every other pair: fail.

### Why not a pull-request gate

An earlier revision of this design ran on `pull_request` and called the base-SHA checkout in
`control/` a trusted control plane. That claim was false, and the falseness is worth stating plainly
because the shape is tempting: on `pull_request`, GitHub evaluates the workflow definition **from the
pull request's own head**. The YAML that decides to check out `control/`, the `if:` guards, the job
list, and the required-check name are all candidate-authored. A candidate can delete the control
checkout, delete the runner invocation, or delete the image job entirely, and the check named
`autopilot container / gate` still reports success — because a required check's identity is a name,
not a behaviour. A control plane that the untrusted party can switch off is a convention, not a
boundary.

The mechanism that would make the definition non-candidate-controlled is an organization-level
required workflow, whose definition lives outside this repository. None is configured here, so it is
not available to rely on and this note does not pretend otherwise.

What survives is the `push` event on `main`: its definition comes from the merged commit, which a
human reviewed and accepted before it landed. That is a real trust boundary, and it is the one this
gate uses. The consequences are stated rather than hidden:

- **The gate is detective, not preventive.** A Dockerfile regression is caught on `main`, attributed
  to one commit, within one run — after it merged. The only pre-merge control over the image recipe
  is human review of the diff, which the "Smoke claims are attested" section already relies on for
  the hostile-recipe case.
- **The check cannot be required on pull requests**, because it never runs on them. Making it a
  required check would block every pull request forever. If branch protection is wanted for the
  image, the honest options are an organization required workflow or a merge queue — both outside
  this repository's control and both their own decision.
- **`concurrency` does not cancel in progress.** Every merged commit gets its own verdict; cancelling
  commit A's run because commit B landed would leave A merged and unmeasured.

Dropping the `pull_request` trigger also removes the bootstrap hole an earlier revision needed: there
is no "base without a runner" case, because the runner and the workflow arrive at the merged commit
together.

The workflow is secretless for candidate execution: no repository/organization secret, token-bearing
build argument, persisted checkout credential, host Docker-socket/workspace mount into candidate
containers, privilege, device, added capability, or host networking. Building uses the hosted runner
daemon, but the built/running image cannot access its socket.

The trusted runner is the sole path-set owner. It derives canonical/installed mappings from
`plugin.json`, parses Dockerfile `COPY` sources, and adds itself, the workflow, launcher, manifest, and
owning tests. `COPY --from=` is rejected outright: its source is a stage or a registry image rather
than a build-context path, so accepting it would let a `COPY --from=other/image devcontainer/toolchain.tsv`
enter the payload set as a hash-verified local file while the image copied bytes from somewhere else.
Detector and Pester call the same function; documentation names categories only.

The runner also owns the receipt shape end to end. `-Mode Initialize` writes the placeholder receipt
that the image and gate jobs upload if measurement never starts, and `-Mode Detect` writes its own
`relevance` and `candidate_only_reason` step outputs. Both used to be hand-written in YAML, which put
the receipt schema and the closed candidate-only reason set in two places; the placeholder written
there named no commit, no path, and no reason, so a reader who downloaded it learned only that
something had not happened.

## Accepted capability

`pip`, SSH, netcat, and DNS clients improve code retrieval and diagnostics. Their presence is accepted
because the runtime already has `curl`, npm, Git, GitHub credentials, unrestricted outbound networking,
and host Docker-socket authority. This baseline adds no daemon, listener, capability, root execution,
secret source, or command-approval bypass. Smoke checks are offline where practical and never contact an
operator-controlled endpoint.

## Gate recovery

The stable check display name is `autopilot container / gate`, reported on `main` pushes only.
Creating the check does not mutate branch protection, and it cannot be a pull-request required check
because it never runs on that event. If an operator wires it into a `main`-branch policy and a
detector defect or upstream outage blocks its own repair, a repository administrator may temporarily
suspend that policy, record the incident, merge a separately reviewed repair, restore the policy, and
verify one irrelevant no-op run plus one relevant image run. The disabled interval and restoration
evidence remain visible in the incident/PR record.

## Residual risks

- The base image stays the floating tag `debian:trixie-slim`; only its resolved ID/digest is recorded per
  run, so two runs may compare different upstream bases. Pinning by digest is a separate decision because
  it changes the maintenance model for the whole image.
- Digest-pinned third-party `.deb` artifacts fail closed on upstream rotation and require a maintenance
  commit to refresh.
- The Copilot CLI and Pester are installed by version, not by integrity digest:
  `npm install -g --ignore-scripts @github/copilot@<version>` and
  `Install-PSResource -Name Pester -Version "[5.6.1]"`. Both pin *which* version is requested — the
  npm tag exactly, and `[5.6.1]` as an exact NuGet range rather than a minimum — but neither pins the
  bytes: a registry can serve different content for an unpublished-and-republished version.
  `--ignore-scripts` is the part that is actually enforced, and it is enforced because the install
  runs as root. No signature check is claimed for Pester, because PSResourceGet's `-AuthenticodeCheck`
  validates only on Windows and this image is Debian. Closing the residue properly means a
  lockfile-per-image maintenance model, which is the same decision the floating base tag defers.
- Provenance files are authored by the image's own build recipe. Host-side attestation proves the image
  agrees with its record and that smoke did not lie about either; it cannot prove a Dockerfile that
  forges both consistently. Human review of the Dockerfile diff is the control for that case.
- **The gate is post-merge.** A regression in the image reaches `main` before the gate reports it. This
  is inherent to the trust model, not an oversight: see "Why not a pull-request gate". Pre-merge
  protection would require an organization required workflow, which this repository does not have.
- Registry and daemon outages during the base build are classified as `base-build-failed`, and during
  the candidate build as `candidate-build-failed` — the second is blocking, so a transient upstream
  failure reads as a candidate defect. Separating infrastructure failure from candidate failure needs a
  new closed outcome that ripples through this note's truth table, the receipt schema, and the gate
  tests; it is deferred rather than papered over.
