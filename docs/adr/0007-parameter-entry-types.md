# Parameter entry types come from the declared funspec, honored as written (no &optional null-widening)

The analysis core seeds a defun's entry environment by binding each parameter to
a type taken **positionally from the defun's own declared funspec**
(`function-get` → `:spec`), and `unknown` where there is no declaration
(consistent with [ADR-0002](0002-declared-typespec-only-v1.md)). The notable,
deliberate choice: an `&optional` parameter's entry type is its **declared type
as written** — elistan does **not** widen it with `null` to model an omitted
argument.

## Why not widen

Widening optionals to `(or T null)` is the *sound* reading (an omitted optional
is `nil` at runtime), but it manufactures incompatibilities against code that
always passes the argument — false positives that violate the zero-false-positive
posture ([ADR-0004](0004-robustness-posture.md)). The funspec is the contract; if
`nil` is possible the author writes `(or T null)`. elistan does not editorialise
a declared type ([ADR-0003](0003-elistan-holds-reins-typespec-toolkit.md)).

## Other seeding rules

- `&rest` parameter → `(list ELEM)` (the rest element type), or `list` when
  untyped.
- `&key` parameters → deferred; v1 targets plain `defun`s. Treated as their
  declared type, else `unknown`.
- Free / special / dynamic variables (outside the lambda list) → `unknown`.

(Minor coordination: typespec's internal `--split-argspecs` is the helper that
splits a funspec arglist into required/optional/rest/keys; promoting it to public
API would let elistan reuse it rather than re-split — ADR-0003.)
