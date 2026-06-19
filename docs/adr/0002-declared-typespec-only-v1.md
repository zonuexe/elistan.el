# v1 wires only the typespec type source; no local inference

elistan resolves a called function's type through pluggable **type sources**
(see [ADR-0003](0003-elistan-holds-reins-typespec-toolkit.md)). v1 wires only
one of them — the **declared typespec** source: `(function-get 'foo 'typespec)`
plus the predicate/pure-function specs typespec already ships. The other sources
(Emacs built-in DB, Elsa-style comments, inference) are deferred. Within the
wired source, v1 does **not** infer the return type of a function defined
locally in the same file; a function with no resolvable type is treated as
`unknown` and passed through.

## Considered options

- **(イ) Declared-lookup only** *(chosen)* — keeps the unit of analysis a single
  self-contained top-level form: no definition-ordering concerns, no fixpoint
  for mutual recursion, and the editor driver can re-analyze just the defun at
  point.
- **(ロ) Infer local function return types** — better coverage of undeclared
  user code, but forces whole-file analysis, definition ordering, and fixpoint
  iteration, and undermines cheap incremental re-analysis.

## Consequences

- v1 coverage is whatever carries a typespec: typespec's shipped pure/predicate
  functions plus user code with explicit declarations. Everything else is
  `unknown`, so the checker emits no false positives from guessed types.
- Adding inference later is additive, but will reopen the per-defun
  analysis-unit assumption.
