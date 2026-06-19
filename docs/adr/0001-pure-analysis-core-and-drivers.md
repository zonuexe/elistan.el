# Pure analysis core, with parsing pushed out to drivers

elistan must serve both an in-editor checker (Flymake/Flycheck-style,
incremental, over a live and possibly-incomplete buffer) and a batch CLI/CI
linter (whole files). To avoid maintaining two analyzers, the **analysis core
is pure**: it consumes already-read forms and returns findings, performing no
I/O and never parsing source text. Two thin **drivers** feed it — a batch
driver (`read` a file → top-level forms) and an editor driver (extract the form
under edit → render diagnostics).

## Consequences

- Settles the open "how does elistan obtain forms?" question for the core: it
  doesn't. Acquisition — file reading, buffer extraction, any macro expansion —
  lives entirely in the drivers.
- **Findings** are the stable interchange between core and drivers, so their
  shape is a deliberate design surface (not yet finalized).
- The core is testable on plain s-expressions, with no buffer or file fixtures.
- Macro-expansion placement and the pure core's injected **expander** are
  detailed in [ADR-0005](0005-macro-handling.md).
