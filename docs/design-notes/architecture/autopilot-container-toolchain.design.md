---
description: Historical container-toolchain contract and retained direct diagnostics after hosted workflow retirement.
globs:
  - plugins/autopilot/devcontainer/**
  - .github/skills/autopilot/devcontainer/**
  - scripts/skalary/Invoke-ContainerToolchainGate.ps1
  - tests/skalary/AutopilotContainer*.Tests.ps1
---

# Autopilot container toolchain

> **Local-first status (plan `2aa7ec`):** the repository-owned hosted workflow was deleted.
> Container scripts and tests remain only as direct diagnostics pending their owning phase-2
> disposition. Nothing in this note makes them a required gate or authorizes an agent/package alias
> to run them. Sections below that describe the former post-merge job are retained as historical
> implementation context, not active operating authority.

Durable contract for the autopilot execution image's agent baseline, its smoke program, and the
comparison gate that measures it. This note is the source of truth the structural tests read.
It lives here rather than in a plan folder because plan folders are archived on completion, and a
contract that disappears from its enforcing test's path is a contract that stops being enforced.

**Applies to:** `plugins/autopilot/devcontainer/**`, `.github/skills/autopilot/devcontainer/**`,
`scripts/skalary/Invoke-ContainerToolchainGate.ps1`,
`tests/skalary/AutopilotContainer*.Tests.ps1`

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

The two recorders read deb822 `Enabled:` differently, and the direction of that difference is
deliberate. The **final** capture is the enforced one, so it is over-inclusive: it records the URIs of
a disabled stanza too. Teaching it to honour `Enabled: no` would let a hostile origin be parked in the
image disabled — invisible to every allowlist check, one `sed` away from being live. The **baseline**
capture is the narrower claim, "what the Debian layer actually resolves from", and is held to the
two-host Debian allowlist, so it honours `Enabled:`. A disabled non-Debian source omitted there is
still caught by the final capture against the wider allowlist, which is why the asymmetry is safe in
this direction and only in this direction. The host-side live scan sides with the final recorder and
ignores `Enabled:` entirely. Ordinary Pester pins each recorder's `Enabled:` handling so a later edit
cannot quietly reverse it.

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
  `tor+http:` origin fails the allowlist instead of being invisible to a pattern that only knows how
  to see http. A source with **no** authority is an origin too — `file:/srv/repo`, `cdrom:[…]/`,
  `mirror+file:///etc/apt/mirrors/debian.list` — and an authority-shaped pattern cannot match any of
  them, so an image sourcing packages from a local tree would pass by naming nothing. Those are
  reported as the pseudo-host `<scheme>:opaque`, which fails the allowlist. Only schemes apt has a
  transport method for are treated this way (`cdrom copy file ftp http https mirror rsh s3 ssh store
  tor`, and `+`-composites keyed on the leading segment), because deb822 permits `Field:value` and a
  scan that read every colon as a source would fail images over `Signed-By:` paths. Authorities and
  authority-less forms are scanned in two separate passes rather than one combined pattern, and that
  is not tidiness: deb822 also permits `URIs:https://evil.example/repo` with no space, and apt
  honours it. A combined `<scheme>:<rest>` pattern binds `scheme=URIs`, swallows the real URL into
  `rest`, discards it as a non-transport scheme, and never re-examines the embedded `https://`,
  because matching resumes past the end of the match — so the origin is absent from the scan and the
  subset check passes on whatever else the tree contained. `apt.conf` and
  `apt.conf.d/*` are scanned too, and a directive that moves the source-list directory both readers
  enumerate out of view fails the read closed — an allowlisted `/etc/apt` that apt never consults
  would otherwise pass. That scan reads a configuration file the way apt does, as a stream of
  statements rather than a list of lines, because every line-shaped assumption is an evasion: apt
  accumulates a statement across newlines until an unquoted `{`, `;` or `}`, so a `Dir::Etc` opened
  as a brace block puts the payload on a line that never names `Dir`; `/* */` is removed with no
  separator in its place, so `D/*x*/ir::Etc::sourcelist` is one token to apt and two fragments to a
  reader that keeps the comment as whitespace; and a statement can begin mid-line after a `;`, so
  `#include` need not start one. Comment stripping is quote-aware for the same reason in reverse —
  `Acquire::http::Proxy "http://p:3128"; Dir::Etc "…";` contains a `//` inside a string, and a
  reader that treated it as a comment would drop the real directive that follows it. The normalizer
  empties quoted *values*, splices out block comments, strips `//` and non-magic `#` comments, and
  keeps apt's magic comments (`#include`, `#clear`, `#x-apt-configure-index`), which apt honours
  wherever a statement may begin and not merely in column 0.

  Statements are not the last layer, though, and stopping there left the classifier blind in a way
  worth naming: apt parses a *word*, stripping embedded quotes and decoding `%XX` escapes as it
  goes, in the tag as much as in the value. Verified against `debian:trixie-slim`, `D"i"r::Etc`,
  `"Dir"::Etc`, `%44ir::Etc`, `"#include"` and `%23include` all relocate the source list or pull in
  a hidden file, while a reader that models only comments and statements is shown `D""r::Etc`,
  `""::Etc` or an undecoded `%44ir` and finds no token at all. So quotes are resolved by position —
  spliced out of a tag, emptied in a value — and `%XX` is decoded after comments are stripped,
  which is the order apt uses and which is why a decoded `#` or `/` cannot forge a comment. The
  price is that a quoted list element (`APT::NeverAutoRemove { "^linux-.*"; };`) is read in tag
  position, so a list of paths that names `Dir` fails the read; that is the direction to be wrong
  in, since the alternative is a tag the candidate can spell in a way this reader cannot see.

  On that normalized text the `Dir` match is deny-by-default: every `Dir` and `RootDir` token is
  rejected unless it is `Dir::Cache`, `Dir::State`, `Dir::Log` or `Dir::Media`, the four subtrees
  Debian's own base images ship (`docker-clean` sets `Dir::Cache::pkgcache ""`) and none of which
  relocates a source list. An allowlist of known-bad prefixes would have to enumerate `Dir::Etc`,
  `Dir::Bin`, a bare `Dir`, and each binary scoping of them; the safe set is four names and is the
  side that does not grow. The token counts only where a tag segment can begin — at a word start or
  straight after a `::` — which is what keeps `DPkg::Chrootdir` and a `/srv/dir/x` left in an
  unquoted value from failing an honest image. `RootDir` is refused unconditionally, including
  `Dir::Cache` under it, because apt prefixes it onto every resolved path — the relative values stay
  reassuringly default while `/etc/apt` resolves somewhere else entirely. Scoping is handled by the
  same token match rather than a separate rule: `Binary::apt-get::Dir::Etc::sourcelist "/opt/hidden"`
  relocates the source list for apt-get alone and leaves the unscoped value untouched, and the `Dir`
  in it is the same token whether or not a scope precedes it. `#include` fails whatever it names,
  because the file it pulls in is not in the tree this scan can vouch for, and `#clear` fails when it
  names `Dir` or `RootDir`, because clearing a value restores a default the scan did not verify.

  The Dockerfile's initial policy refuses the same shapes at the first layer, and it needs both
  halves for the same reason: its `apt-config dump` grep covers `Binary::…::Dir`, `Binary::…::RootDir`
  and bare `RootDir`, while `apt-config shell` assertions on `Dir::Etc::sourcelist/f` and
  `Dir::Etc::sourceparts/d` pin where those paths *resolve*, which is the only check a `RootDir`
  cannot leave looking default.

  Relocation is only one way to make an allowlisted tree meaningless, and the other two change no
  path at all. A **proxy** leaves every hostname exactly as written: apt still asks for
  `deb.debian.org`, the proxy answers, and the recorded file, the live tree and the smoke claim all
  compare equal while the packages come from somewhere else. **Trust weakening** is what makes that
  substitution stick, since a signature check is the one thing a proxy cannot forge — and it has two
  spellings, one in `apt.conf` (`APT::Get::AllowUnauthenticated`, `Acquire::AllowInsecureRepositories`,
  `Acquire::Check-Valid-Until "false"`, `Acquire::https::Verify-Peer "false"`, a redirected `CaInfo`
  or `gpgv::Options`) and one in the source entry itself (`deb [trusted=yes] …`, deb822
  `Trusted: yes`). Both classes are refused on the same normalized statement text as `Dir`, and by
  segment rather than by list: any tag segment containing `proxy` fails, as does any segment naming
  `Allow*`, `Trust*`, `Untrusted`, `Unauthenticated`, `Insecure*`, `Weak*`, `Check-Valid-Until`,
  `Check-Date`, `Verify-Peer`, `Verify-Host`, `CaInfo`, `CaPath` or `gpgv`. The value is not read.
  Agreeing with apt's `StringToBool` on every spelling of true is a comparison that fails silently
  when it is wrong, and an honest image has no reason to name any of these at all — verified against
  the six `apt.conf.d` files `debian:trixie-slim` and Docker's own layers ship, none of which does.
  The source-entry form is checked per file as an option rather than as a word, so `Signed-By:
  /etc/apt/trusted.gpg.d/debian-archive-trixie-stable.asc` — a keyring path Debian itself writes —
  is not mistaken for a waiver; an option present with an empty value fails, because apt reads that
  value from a continuation line this reader does not join.

  `APT_CONFIG` is the same attack from outside the tree. apt reads the file it names *before*
  `/etc/apt/apt.conf`, and that file can relocate, unauthenticate or proxy everything the scan
  enumerates from a path the scan never sees — so the whole configuration read is worth nothing while
  it is set. The gate therefore reads the environment the image hands every container it starts,
  with `docker inspect` against the container it just created rather than against the tag, so a
  `docker create` that ever gains an `--env` cannot become invisible to it. Any non-empty value is
  refused, which is also apt's own condition for honouring the variable, and the proxy environment
  variables (`http_proxy` and its seven siblings) are refused on the same grounds as the directives.
  The read is bounded twice — total bytes and entry count — and anything that is not a JSON array of
  strings is `unreadable` rather than clean, because an ununderstood read is not evidence of an empty
  environment. `null`, which is what Docker reports for an image that sets nothing, is the one shape
  with nothing to reject. Failures reach the receipt as `attestation-image-env:<reason>` and stop the
  attestation before any `docker cp`: a tree apt may never read is not worth copying out.

  The Dockerfile mirrors all three refusals, at the layer that installs and again at the last root
  layer — a policy present once is a policy the other layer is running without, and the final layer
  is what covers whatever a maintainer adds at the documented extension anchor. The build cannot
  reuse the host reader, so it asks apt: `apt-config shell` on eleven trust keys that must not be
  true and four verification keys that must not be false, since `apt-config dump` prints built-in
  defaults and a presence grep would fire on an untouched image. The source-option check runs after
  the source files are discovered and before their hosts are validated, because the waiver names no
  new host and every later check passes on it.

  Any enumeration or read error fails the read closed rather than reporting the hosts it managed to
  read, and so does a configuration file over 256 KB — that scan is character work on the *host*, so
  an image can spend the gate's time by shipping a file large enough to be worth minutes to read,
  and a file this scan did not read is a file it cannot vouch for. So does **any**
  symlink, junction or other reparse point at or under the tree root: a `-File` enumeration returns
  nothing for a redirected directory and reports no error either, so a tree whose `sources.list.d`
  points elsewhere would otherwise be read as the empty set and pass on the half it could see. Every
  one of these failures carries a bounded reason — the condition that fired and, where a file is at
  fault, its name reduced to a fixed alphabet and 64 characters, since that name is
  candidate-authored text bound for the receipt — and it reaches the receipt as
  `attestation-apt-config-unreadable:<reason>`. A post-merge job's only audience is whoever opens
  that receipt, and "unreadable" alone does not distinguish a copy that never ran from a
  configuration that relocated itself;
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

Not every smoke failure belongs to a case. Ten whole-run conditions — running as the wrong user, a
writable `/usr/local/bin`, an unreadable or duplicate-keyed manifest, a case-count mismatch, missing
provenance files, a manifest or provenance digest that could not be computed, an encoder failure, and
output over the size bound — used to collapse into a bare `state=fail`, and the receipt could then say
only "reported failure without naming a case".
`skalary/container-toolchain-smoke@1` therefore carries a required `reasons` array drawn from a closed
vocabulary: `case-count-mismatch`, `encoder-failed`, `manifest-digest-unavailable`,
`manifest-duplicate-case`, `manifest-unreadable`, `not-autopilot-user`, `output-oversize`,
`provenance-digest-unavailable`, `provenance-incomplete`, `usr-local-bin-writable`. The vocabulary is
closed so a broken or hostile image cannot use the field as a free-text channel into the job summary. It is empty on `pass`, and a `fail`
with neither a failing case nor a reason is rejected as invalid output — a verdict with no diagnosis is
not a verdict. The schema version is not bumped because the schema has never shipped outside this
branch; the field is required from its first release.

Two of those reasons describe the encoder itself failing, so the object carrying them is the one the
script emits when it could not build a real one: `state=fail`, a named reason, and nothing else — no
digests, no cases. Validation therefore treats a **degraded** payload (`state=fail` with at least one
reason) as structurally acceptable when its digests are empty and its case list does not match the
manifest, rather than rejecting it as malformed. Rejecting it replaced the one thing the failing run
managed to say with the generic `candidate-output-invalid`, which is how `encoder-failed` and
`output-oversize` could never reach a receipt. The relaxation is bounded on both sides: the reason set
stays closed, a `fail` with no reason at all is still invalid, and nothing is relaxed for `state=pass`
— attestation agreement is checked against exactly those digest and origin fields, so a passing claim
with an empty digest is still rejected. It is safe because the orchestrator returns
`candidate-smoke-failed` before attestation ever consumes them.

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
   publish no cache or image. **Every** base-side failure is candidate-only evidence, including one
   that happens while *inspecting* the base image rather than building it: a base whose size cannot be
   read is a base that cannot be compared, which is the same fact as a base that would not build. It
   is recorded as `base-build-failed` with a candidate-only reason and a diagnostics-log entry naming
   the stage, never as a blocking error against a candidate that already built and smoked clean.
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

That applies to the *unexpected* failures too, and this is where it is easiest to lose. A blocking
`unexpected-error` — a base image whose identity will not resolve, a platform that does not match the
one requested, a daemon that reports a different architecture — is raised by throwing, and a throw
that carries only a sentence leaves the receipt saying an environment check failed without the
`docker` output that says why. Each of those paths therefore writes the failing stage and its bounded
process tail to the diagnostics log *before* throwing, and appends the tail to the message; the
top-level handler records the terminating message and its script stack trace the same way. The
diagnostics log is the artifact these runs leave behind, so a condition that reaches it is
diagnosable from the upload alone and does not require reproducing a hosted-runner environment.

The receipt, provenance file, summary, and diagnostics log are uploaded under `if: always()` for 14
days. The internal 35-minute limit reserves ten minutes before the 45-minute job timeout for
finalization/upload. If the hosted runner itself is killed before upload, the final gate records the
image job's `timed_out`/non-success conclusion and missing artifact as the durable Actions diagnosis.
The job summary states outcome, blocking state, comparison, both image sizes, the delta against the
advisory threshold, stage timings, smoke result with any failed cases, and the diagnostic — a summary
that omits the numbers forces a reader into the artifact for the one fact the summary exists to give.
If a comparable receipt exceeds 250 MiB, finalization requires `assets/decisions/image-size-exception.md`.
The rule is stated in terms of "a growth measurement", not "the gate receipt", because the gate is not
the only channel that can produce one and pretending otherwise made the shipped tree read as a
violation of its own note. A receipt closes to candidate-only whenever no comparable base exists —
including the case where the base commit predates the build context the payload mapping needs — and a
candidate-only receipt carries `deltaBytes: null`. The size question still has an answer in that case,
so it is measured directly by two builds on one host and recorded as
`skalary/container-toolchain-image-growth@1` under the plan's `assets/measurements/`. That artifact is
hand-run and hand-recorded: it names its method, both commit SHAs, both resolved image IDs, the
platform, the daemon and CLI versions, and the build arguments, precisely because nothing validates it
and its credibility rests on being reproducible from what it states. It is permitted **only** when the
receipt for the same commit is not comparable, and it never substitutes for a comparable receipt that
exists. When both exist, the receipt is the one that counts.

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
- **`concurrency` does not cancel in progress, and its group is unique per commit.** Every merged
  commit gets its own verdict; cancelling commit A's run because commit B landed would leave A merged
  and unmeasured. `cancel-in-progress: false` alone does not give that guarantee — a group keyed on
  the ref alone still *queues* runs, and GitHub keeps at most one pending run per group, so three
  commits landing during one 45-minute image job leave the middle one silently superseded and never
  measured. The group therefore includes `github.sha`, which makes each commit its own group: nothing
  queues behind anything, and no merged commit can be displaced by a later one. The per-commit key
  costs concurrent runners rather than correctness, which is the right side to spend on for a gate
  whose entire claim is "every merged commit receives a verdict".

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

The placeholder must also state relevance rather than assume it. A placeholder that always says
`irrelevant` is the one reading under which a lost measurement job disappears: the job that writes it
only runs when relevance is `true`, so the claim is false exactly when it matters, and a reader
downloading the surviving artifact would be told the commit did not touch the image. `Initialize`
therefore takes the detector's verdict and closes to `unexpected-error`, `relevant: true`,
`blocking: true` for a relevant commit, keeping `irrelevant` for the commit that genuinely changed
nothing.

The final receipt carries the identities too. It is the only artifact that always exists, and when the
image job is skipped it is the only one there is — so a verdict that named no commit could not be
attributed to the change it judged. `VerifyResult` therefore receives the base and candidate SHAs, the
detector's candidate-only reason, the count of relevant paths, and the image job's measured
`comparison` plus candidate-only reason. The latter two are outputs written by the runner from the
terminal measurement receipt; they are never inferred from a successful job conclusion because a
base build failure is itself a successful candidate-only measurement. `VerifyResult` writes those
values into the same `identities`, `comparison`, `candidateOnlyReason` and `diagnostic` fields. The
path *names* cannot travel that wire: step outputs are restricted to a bounded `[A-Za-z0-9._-]`
alphabet precisely so nothing candidate-shaped reaches `$GITHUB_OUTPUT`, and a repository path
contains `/`. The count travels, and the detector uploads its own receipt as an artifact so the names
remain recoverable from the run. An absent count is reported as `unreported`, never as zero, because
those are different claims.

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

### The gate is red on `main`

A detective gate is only detective if someone finds out. Post-merge failure has no pull request to
turn red and no author waiting on a check, so a red run's entire audience is whoever happens to open
the Actions tab — which is how a regression sits on `main` for a week. Two things close that: the run
announces itself, and the response is written down before it is needed rather than improvised by
whoever is on call.

**Notification.** A `notify` job runs `if: always() && needs.gate.result != 'success'` and opens — or
comments on — a repository issue titled `autopilot container gate red on main at <sha>`, carrying each
job's conclusion, the run URL, and a pointer to this section. One issue per commit, so a repeatedly
failing commit does not manufacture a queue. It is the only job in the workflow granted more than
`contents: read`: it takes `issues: write` and nothing else, holds no checkout, and runs no gate code,
so the widened token never sits in a job that touches candidate-controlled input. The choice is
deliberate over the alternatives — email needs a secret this workflow refuses to hold, and a
notification that lives in one person's inbox is not repository-visible evidence. If Issues are
disabled for the repository, this job fails, which is itself visible on the same run rather than
silent.

**Response.** The gate reports one commit's verdict, and that commit is named in the receipt, so the
first question is always which failure it is:

1. **Read the verdict, not the red X.** Download the run's `container-toolchain-*` artifacts. The
   receipt's `outcome` is the diagnosis: `candidate-build-failed`, `candidate-smoke-failed` and
   `candidate-output-invalid` are the image; `base-build-failed`, `base-timeout` and
   `candidate-timeout` are the comparison or the runner, and are advisory or environmental rather
   than statements that the image is broken. `unexpected-error` means the gate itself hit a condition
   it does not model — the diagnostics log carries the failing stage and the process tail.
2. **Decide whether `main` is currently shipping a broken image.** Only the three candidate outcomes
   above mean it is. The image is consumed by autopilot container runs, not by the repository's own
   CI, so the blast radius is agent execution rather than the merge pipeline.
3. **Revert first if it is.** The offending commit is named in the receipt's `identities.candidateSha`.
   `git revert <sha>` on a branch, open it as an ordinary pull request, and merge it — the revert
   itself is a `main` push, so the gate re-runs and the green run on the reverted state *is* the
   verification. Reverting is preferred over fixing forward because the gate cannot tell you whether
   a fix works until after it has merged; a revert restores a state that already had a green verdict.
   Fix forward only when the failure is a base-side or timeout outcome, where nothing is broken to
   restore.
4. **Re-run before believing an infrastructure story.** `base-build-failed` and the timeout outcomes
   are the ones a registry or daemon outage produces. Re-running the workflow on the same commit
   distinguishes a transient outage from a real regression, and costs one run.
5. **Close the loop in the issue.** The `notify` issue is the incident record: the cause, the revert
   or fix commit, and the green run URL go there, and it is closed only after a green run exists for
   a commit on `main`. An issue closed without one is a gate whose failure was noted and dropped.

If a red gate persists across a revert and a re-run, the failure is in the gate rather than the image;
suspend any branch policy that depends on it using the procedure above rather than merging past it
untested.

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
