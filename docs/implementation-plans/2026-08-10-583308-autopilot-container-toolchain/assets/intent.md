# Intent

## Goal

Give autonomous agents a predictable, useful command-line baseline inside the autopilot container, starting with `ripgrep`, so routine repository exploration and debugging do not fail because common tools are absent.

## Desired outcome

The shipped image contains a curated set of search, navigation, archive, native-build, and diagnostic utilities installed during image build. Common command names behave consistently despite Debian package aliases, and a non-root runtime smoke test proves the tools work rather than only exist in Dockerfile text. Acquisition and comparison inputs are bounded and reported; byte-for-byte rebuilds across floating upstream releases are not promised.

## Success signals

- `rg`, `fd`, and `bat` work under their conventional names as the `autopilot` user.
- Agents can inspect archives/files, compile common native dependencies, run lightweight Python helpers, inspect processes/network state, lint shell, and query SQLite without modifying the image at runtime.
- A clean image build fails if a required tool is unavailable or nonfunctional.
- The measured image-size increase is reported against an advisory 250 MiB threshold so tool value and distribution cost remain visible.

## Non-goals

- Installing editors, browsers, language-version managers, cloud-provider CLIs, database servers, or background daemons.
- Giving the container more privileges or changing autopilot's plan, command-approval, authentication, Docker-socket, or timeout contracts.
- Matching the Windows Sandbox toolchain; that runtime has a separate cache and lifecycle.
- Allowing per-run package installation as a substitute for a reproducible image.

## Definition of done

- The approved package baseline is built into the canonical autopilot Dockerfile from trusted Debian repositories with no recommended-package expansion.
- Debian aliases are normalized to `fd` and `bat`.
- Functional smoke tests pass in the built image as the non-root user, distribution copies are synchronized, and the size delta is reported with any advisory-threshold exceedance explained.
