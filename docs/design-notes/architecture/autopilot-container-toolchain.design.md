---
description: Local autopilot container toolchain manifest, build, and direct smoke diagnostics.
globs:
  - plugins/autopilot/devcontainer/**
  - .github/skills/autopilot/devcontainer/**
  - tests/skalary/AutopilotContainer.Tests.ps1
---

# Autopilot container toolchain

Skalary has no hosted container gate. The image is built when container autopilot needs it, and an
operator may run the smoke command directly. Do not add comparison runners, receipts, CI adapters,
baseline images, or image-size policy.

## Source of truth

`plugins/autopilot/devcontainer/toolchain.tsv` is the only additional-tool inventory. Each
non-comment line has exactly three tab-separated fields: stable case ID, Debian package, and command.
The Dockerfile installs that package column and the smoke script contains one `CASE:<id>` block for
each row. `tests/skalary/AutopilotContainer.Tests.ps1` checks these three views and the installed
plugin copy for exact agreement.

| Case ID | Capability | Debian package | Conventional command |
|---|---|---|---|
| `rg-search` | Text search | `ripgrep` | `rg` |
| `fd-find` | File discovery | `fd-find` | `fd` |
| `bat-render` | File rendering | `bat` | `bat` |
| `tree-list` | Tree navigation | `tree` | `tree` |
| `less-version` | Paging | `less` | `less` |
| `file-type` | File typing | `file` | `file` |
| `zip-create` | Zip creation | `zip` | `zip` |
| `unzip-extract` | Zip extraction | `unzip` | `unzip` |
| `rsync-copy` | File synchronization | `rsync` | `rsync` |
| `native-build` | Native build | `build-essential` | `cc` |
| `python-run` | Python helpers | `python3` | `python3` |
| `python-venv` | Python virtual environments | `python3-venv` | `python3` |
| `python-pip` | Python package client | `python3-pip` | `python3` |
| `shellcheck-valid` | Shell linting | `shellcheck` | `shellcheck` |
| `process-self` | Process inspection | `procps` | `ps` |
| `lsof-open` | Open-file inspection | `lsof` | `lsof` |
| `ip-loopback` | Network inspection | `iproute2` | `ip` |
| `dig-version` | DNS diagnostics | `bind9-dnsutils` | `dig` |
| `nc-help` | TCP diagnostics | `netcat-openbsd` | `nc` |
| `ssh-version` | SSH client | `openssh-client` | `ssh` |
| `sqlite-query` | Local structured query | `sqlite3` | `sqlite3` |

## Container rules

- Build from `plugins/autopilot` with `devcontainer/Dockerfile`.
- Keep root-owned setup above the literal `# Non-root user` extension anchor.
- Run the smoke script as the non-root `autopilot` user.
- Keep `fd` and `bat` aliases root-owned and `/usr/local/bin` non-writable.
- Keep package-source and downloaded-artifact checks in the Dockerfile. They protect the image build;
  they do not justify a second host-side gate.
- The smoke output remains bounded and machine-readable because the launcher may display it, but it is
  diagnostic output rather than signed or durable evidence.

Direct check:

```powershell
docker build -t skalary-autopilot -f plugins/autopilot/devcontainer/Dockerfile plugins/autopilot
docker run --rm --network none --entrypoint container-toolchain-smoke skalary-autopilot
```
