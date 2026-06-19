# Walker: env-threading by two functions, divergence-aware confluence

The walker types a function body by threading the type environment through
forms. Two cooperating pure functions:

- **`type-expr (FORM ENV) → (:type T :env ENV')`** — the value type, and the
  environment after the form (carrying `setq` and other mutation effects).
- **`recognise (FORM ENV) → refinement`** — the condition effect (the ADR-0009
  refinement). Separate from typing, so recognisers stay pure.

The split: **env-out carries mutation; the refinement carries the condition
effect.** `if`/`cond`/`and`/`or` orchestrate both.

## Control forms

- **`if`/`when`/`unless`**: type the test (value + `env'`); `recognise` it → `R`;
  type `then` under `apply(R.true, env')` and `else` under `apply(R.false, env')`.
- **`cond`**: nested `if`s; each clause is typed under the accumulated false-env
  of the prior tests.
- **`and`/`or`** (double duty): the value-typer threads left-to-right under
  *progressive narrowing* — `(and e1 e2)` types `e2` under
  `apply(recognise(e1).true)`; `or` is the dual. Value type `(or null Tlast)` for
  `and`, the union of the non-nil arms for `or`. The `and`/`or` *recogniser*
  composes the operands' refinements per [ADR-0009](0009-narrowing-representation.md)
  (and-true precise, and-false widened; or dual).

## Confluence is divergence-aware

A branch may not reach the confluence — `throw`, `signal`/`error`, `cl-return*`,
`keyboard-quit`, … transfer control away. Such a form has value type **`never`**
(bottom). Confluence then joins/unions **only the branches that can fall
through** (value ≠ `never`):

- both branches fall through → value `Tt ∪ Te`, env `join(env_t, env_e)` (base case);
- one branch is `never` → value and env come from the *other* branch alone. This
  is the **guard-clause / early-exit narrowing** pervasive in Elisp:
  `(unless (stringp x) (error …))` leaves `x : string` afterwards;
- both `never` → the whole form is `never` (code after is unreachable).

Divergence is **data-driven**: a called function whose declared return type is
`never` makes its call diverge, so the fact lives in the type source, not in
hardcoded lists (ADR-0002/0003).

## Dead-branch signal

A `dead-branch` finding (category 2) fires when the test's *value type* is
provably non-nil (always true) or `null`/`never` (always false).

## v1 approximations

- **`catch` / `condition-case`** (where throws/signals *land*) are approximated:
  type the body, but do not propagate body narrowing into a handler (an error may
  occur mid-body), and widen the form's value conservatively (union with
  `unknown` / the handler values). Precise per-tag throw tracking is deferred.
- **`unwind-protect`**: the body determines value and flow; cleanup does not
  affect the value type.

## Dependency

Divergence-by-data needs noreturn functions (`error`, `signal`, `throw`,
`user-error`, `cl-return*`, …) to carry return type `never` in the type source;
typespec declares none of them yet. v1 ships a small built-in noreturn set as a
fallback until the specs exist (coordination, like the gradual dynamic).
