## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] APT source validation walked regular files under /etc/apt, missing symlinked or reconfigured source paths that apt-get can consume.
- [1.1] [src:code-review] [sev:High] Rubber-duck: recursive apt dependency candidates included uninstalled alternatives, so dpkg-query could abort provenance capture under pipefail.
- [1.1] [src:code-review] [sev:Low] Rubber-duck: deb822 Enabled parsing recognized no but not false or 0, misclassifying disabled sources as active.
- [1.1] [src:code-review] [sev:High] APT generic path checks did not reject Binary::apt-get::Dir overrides, allowing apt-get to consume a different source set.
