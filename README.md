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

Early draft. The flow-sensitivity layer is in place:

- A type environment (`var -> type`): `elistan-env-make` / `-get` / `-set`.
- `elistan-env-narrow` — apply a guard/assert predicate tested on a variable
  and obtain the refined environments for each branch.
- `elistan-env-join` — union variable types at a control-flow confluence.

For example, narrowing `x : (or string integer)` with `(:guard! string)` gives
`x : string` on the true branch and `x : integer` on the false branch, and
joining the branches recovers `(or string integer)`.

Still to come: the front-end that walks `if` / `cond` / `when` / `and` / `or` /
`let`, resolves calls, and drives the environment.

## Development

```sh
make check   # requires the typespec sources at ../emacs-typespec
```

Override the foundation path with `make check TYPESPEC=/path/to/emacs-typespec`.

## License

[GNU General Public License, version 3](https://www.gnu.org/licenses/gpl-3.0).
