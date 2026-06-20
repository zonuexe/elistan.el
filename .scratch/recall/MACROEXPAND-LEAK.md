# Discovered bug: order-dependent inference via macroexpand-all side effects

> **RESOLVED** (`fix(walk): deterministic macroexpand`). Root cause: `macroexpand-all`
> applied **compiler-macros** (e.g. `char-before` → `(char-after (1- (or pos
> (point))))`) whose availability grows as files are processed (autoloaded
> libraries install them), so expansion — and thus inference — was order-dependent
> and surfaced findings about *inlined library internals*. Fix:
> `elistan-walk--macroexpand` neutralises `macroexp--compiler-macro` so the walker
> analyses the source as written. Sweep is now verified order-stable (forward =
> reverse). The `and`/`or` constant-guard feature was then re-landed cleanly.
> The analysis below is the original investigation.

Found while implementing `and`/`or` constant-guard detection (the last in-scope
recall gap). That feature was **reverted** because, on the corpus, it produced
**order-dependent findings** — a symptom of a deeper pre-existing bug.

## Symptom

A finding fires only after other files have been processed in the same batch
session:

```
jsonian BEFORE (isolated): 0 findings
jsonian AFTER 150 files:    1 finding   ("rest of `or' unreachable")
```

The flagged operand is a bare parameter `pos` that is `unknown` in isolation but
becomes **provably non-nil** after processing other files — i.e. type inference
is *order-dependent*.

## Root cause (characterised, not yet fully isolated)

`elistan-walk-defun` runs `macroexpand-all` on each defun body. Macro expanders
have **global side effects**: across 150 files the global CL class registry
grows.

```
before: cl-classes (symbols with a 'cl--class prop) = 81
after : cl-classes = 105   (+24)
```

Ruled out (all *unchanged* before/after): `'typespec` function properties,
`elistan-source-local`, `elistan-source-builtins`, `typespec-eval-types-class-parents`,
`elistan-walk-class-slots`, `typespec-resolvers`, `defun-declarations-alist`,
`char-before`/`=` resolved specs.

So a globally-registered struct/class (via expansion of `cl-defstruct` /
`cl-defmethod` / `pcase` struct patterns inside bodies) changes a later file's
inference — most likely through typespec's class handling that still falls back
to the **live** EIEIO/`cl--find-class` (`typespec-eval-types-class-subtype-p` →
`child-of-class-p`, and the `object-of-class-p` op). The exact path from a
registered class to `pos` becoming non-nil is not yet pinned down.

## Why it matters (beyond the reverted feature)

The single-file batch *sweep* runs all files in one process, so the leak is
present there too. The baseline 20 findings are stable for a *fixed* file set +
order (verified: datetime/logview/lsp reproduce in isolation), but the result is
**not order-independent** — and **project mode** (`elistan-project-check`,
multi-file in one session) could therefore produce order-dependent findings,
including potential false positives in the existing `if`/`cond`/call categories.
This is a latent reliability gap in the zero-FP guarantee for multi-file runs.

## Repro

```elisp
;; emacs -Q --batch -L . -L ../emacs-typespec  (load elistan-batch)
(elistan-elsa-register-typed-dbs (file-expand-wildcards ".../elsa-typed-*.el"))
(length (elistan-batch-check-file ".../jsonian.../jsonian.el"))  ; => 0
;; ... process ~150 other elpa files via elistan-batch-check-file ...
(length (elistan-batch-check-file ".../jsonian.../jsonian.el"))  ; => 1
```

## Fix directions (for a focused session)

1. **Isolate macroexpand-all** so a defun-body expansion cannot mutate global
   state — e.g. expand with the CL-struct/EIEIO registration functions
   neutralised (`cl-letf` around `cl-struct-define` / `eieio-defclass-internal`),
   or snapshot+restore the relevant registries around `macroexpand-all`.
2. **Make typespec class subtyping fully static** — do not fall back to live
   `child-of-class-p` / `cl--find-class`; rely only on the supplied
   `typespec-eval-types-class-parents`. (Removes the live-class dependency that
   the leaked registrations perturb.) Then re-pin the `pos` path.
3. After the leak is fixed, **re-land `and`/`or` constant-guard detection** — its
   logic is sound (it reuses the if/cond `true-never`/`false-never` signal); the
   `marginalia.el:619` case reproduces in isolation and is a genuine true
   positive. The reverted diff is recoverable from this session's history.
```
```
