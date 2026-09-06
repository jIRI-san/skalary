# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- Use one file-only step so the run exercises execution, validation, archival, publication, and close
  detection without changing production behavior.
- Leave the generated pull request open until the launcher exits, then close it without merging.
