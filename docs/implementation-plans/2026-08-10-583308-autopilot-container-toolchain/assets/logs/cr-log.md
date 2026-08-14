## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] APT source validation walked regular files under /etc/apt, missing symlinked or reconfigured source paths that apt-get can consume.
- [1.1] [src:code-review] [sev:High] Rubber-duck: recursive apt dependency candidates included uninstalled alternatives, so dpkg-query could abort provenance capture under pipefail.
- [1.1] [src:code-review] [sev:Low] Rubber-duck: deb822 Enabled parsing recognized no but not false or 0, misclassifying disabled sources as active.
- [1.1] [src:code-review] [sev:High] APT generic path checks did not reject Binary::apt-get::Dir overrides, allowing apt-get to consume a different source set.
- [1.2] [src:code-review] [sev:Low] Rubber-duck: an unreadable or empty runtime manifest could emit state pass with an empty cases array.
- [1.3] [src:code-review] [sev:Med] Contract test checked install fragments but did not reject extra packages appended to the manifest-derived array.
- [1.3] [src:code-review] [sev:Med] Injected-origin fixture used a test-side scanner and did not prove the Dockerfile fallback exited nonzero or ordered validation before update.
- [1.3] [src:code-review] [sev:Med] Smoke COPY index lacked a nonnegative assertion, so a missing COPY still compared less than USER.
- [1.3] [src:code-review] [sev:Med] Closed-schema assertions parsed only fallback JSON, allowing fields to be added to primary output.
- [1.3] [src:code-review] [sev:Low] Rubber-duck: the documented literal # Non-root user extension anchor was not asserted, so launcher extension insertion could silently stop.
- [1.3] [src:code-review] [sev:Low] Rubber-duck: origin red mutation could pass through exact-token failure instead of proving the parsed fallback rejected unknown hosts.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck: missing provenance files did not force smoke state fail, and the remaining-input digest still looked valid.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck re-review: nonempty directories passed provenance prerequisites, and failed child hashes could still produce a valid aggregate digest.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck final review: jq encoder failures could leave blank stdout while overall state remained pass.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck review: intermediate jq failures did not force the static failure JSON, despite setting aggregate state fail.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck review: final state evaluation overwrote printf failure, allowing exit zero when stdout could not be written.
