# elistan

A flow-sensitive type checker for Emacs Lisp, built on top of the
[`typespec`](https://github.com/zonuexe/emacs-typespec.el) type-operations
foundation.

## Relationship to typespec

`typespec` owns the **meaning** of the type notation — the type algebra
(union / intersection / difference), subtyping, type-level evaluation, and the
guard/assert *narrowing effect* (`typespec-eval-call-narrowing`). It is a pure
type-operations library, usable by any consumer (a checker, or a
property-based testing tool).

`elistan` is one such consumer: a **type checker**. It owns the
**orchestration** of those operations over real code — tracking variable types
and refining them across control flow.

## Current status

The v1 checker front-end is implemented (design in `docs/adr/`, scope in
`.scratch/checker-frontend/PRD.md`, glossary in `CONTEXT.md`). It walks a
function body, threads a type environment through control flow (with
narrowing and guard-clause / early-exit narrowing), and reports three kinds of
finding:

- **call-type-mismatch** — an argument provably incompatible with the called
  function's declared parameter type;
- **dead-branch** — a condition that is provably always true or always false
  (e.g. testing `(integerp x)` where `x` is known to be a string);
- **return-type-mismatch** — a body whose type is incompatible with the defun's
  declared return type.

The posture is deliberately quiet: a finding is emitted only when an
incompatibility is *provable*, so unknown or partial information never produces
a false positive.

### Usage

Batch / CI:

```sh
emacs -Q --batch -L . -L ../emacs-typespec \
  -l elistan-batch --eval '(elistan-batch-run)' FILE.el ...
```

In the editor — enable the Flymake backend in `emacs-lisp-mode`:

```elisp
(add-hook 'emacs-lisp-mode-hook #'elistan-flymake-setup)
```

Function types are resolved from `typespec` declarations, typespec's builtin
registry, and elistan's own fallback table.

## Development

```sh
make check   # requires the typespec sources at ../emacs-typespec
```

Override the foundation path with `make check TYPESPEC=/path/to/emacs-typespec`.

## License

[GNU General Public License, version 3](https://www.gnu.org/licenses/gpl-3.0).
