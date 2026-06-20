# Call findings only against author-written contracts, not builtin databases

A `call-type-mismatch` finding is emitted only when the called function's type
comes from an **author-written source** — an in-file annotation
(`elistan-source-local`, e.g. an Elsa `;; (NAME :: TYPE)` comment) or a user
`typespec` declaration (`function-get`). Types drawn from builtin *databases*
(typespec's builtin registry, an imported Elsa type database, elistan's fallback
table) are **not** used to flag a call.

## Why

Emacs builtins are leniently polymorphic, and no imported database captures every
leniency: `(message nil)` clears the echo area, `mapconcat`'s separator is
optional, `substring` accepts a vector, and so on. Checking arguments against
such necessarily-incomplete types produces false positives on perfectly valid
code, violating the zero-false-positive posture
([ADR-0004](0004-robustness-posture.md)). An author who writes a type annotation
is stating a *contract*; a coverage database is a *heuristic*.

This was found concretely by running the checker (with Elsa's ~327 builtin types
loaded) over real elpa packages: every `call-type-mismatch` from a builtin was a
false positive, while genuine dead-branch findings were correct.

## Consequences

- Builtin/database types still drive **narrowing** and **result typing**, so
  dead-branch and return-type findings — and downstream precision — keep the full
  benefit of broad coverage without risking call false positives.
- On code without annotations, elistan reports dead-branch and return-type
  findings but few call mismatches. Call checking activates as authors annotate
  (the typespec / Elsa workflow).
- Builtin type databases are therefore safe to load aggressively for coverage,
  since they can never *manufacture* a call finding.
