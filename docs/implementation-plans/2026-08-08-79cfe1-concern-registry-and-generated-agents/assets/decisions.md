# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Do not change the taxonomy.** The settled seven concerns and meanings remain fixed; this plan changes authorship and generation only.
- **One registry is authoritative.** Tests, guides, maps, manifests, and agent inventory derive from or validate against it instead of re-declaring the list.
- **Generate both review surfaces.** Shared concern bodies are authored once with explicit code-review and design-review variants produced at sync time.
- **Use the established sync-and-drift pattern.** A deterministic writer plus `-WhatIf` validation follows the `Sync-PluginScripts.ps1` precedent.
- **Rejected: registry-only centralization.** A registry that generates nothing is another copy and does not make drift structurally impossible.
