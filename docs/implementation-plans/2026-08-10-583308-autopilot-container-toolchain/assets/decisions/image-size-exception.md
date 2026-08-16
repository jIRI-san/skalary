# Image size exception

The final direct-build measurement against `origin/main` at `c961786` reports:

- Candidate image: 2,856,022,233 bytes
- Base image: 2,519,751,105 bytes
- Growth: 336,271,128 bytes (320.69 MiB)
- Advisory threshold: 250 MiB

The growth is accepted for this release. The curated baseline adds the .NET 10 SDK plus
agent-facing diagnostics, build, archive, network, database, and shell-analysis tools. These
packages remove repeated runtime setup and make the container usable offline after build.

The threshold is advisory, not a correctness or security gate. The measured cost remains visible
in the plan evidence and must be reconsidered when the baseline changes. Future additions should
prefer replacing or removing existing packages rather than increasing the image further.
