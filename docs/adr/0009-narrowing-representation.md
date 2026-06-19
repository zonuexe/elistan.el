# Narrowing representation: per-variable refinements, composed by type algebra, widened on disjunctive branches

The narrowing front-end recognises a condition, represents its effect as a
**refinement**, composes refinements for `and`/`or`/`not`, and applies the
result to the type environment.

## Refinement representation

A refinement is a declarative, environment-independent map
**`variable → (:true P :false N)`**, where `P` and `N` are types to *intersect*
with the variable's current type to get the true-branch and false-branch types.
Application is `env[v] ∩ P` (true) and `env[v] ∩ N` (false). One representation
unifies guards and relational conditions:

| condition | `P` (true) | `N` (false) |
| --- | --- | --- |
| `(stringp x)` (`:guard!`, total) | `string` | `¬string` (complement) |
| `(stringp x)` (`:guard`, partial) | `string` | `mixed` (no-op) |
| `(eq x 'foo)` | `(const foo)` | `¬(const foo)` |
| `(> x 5)` | `(integer 6 *)` | `(integer * 5)` |
| `(null x)` / `(not x)` | `null` | `¬null` |
| `(memq x '(a b))` | `(or (const a) (const b))` | `¬…` |

Rejected: environment-transformer closures (opaque — not inspectable or
testable) and the current whole-environment-pair shape (handles only one guarded
variable). The existing `elistan-env-narrow` becomes the *application* step; a
new *recognition → refinement* layer feeds it.

This split follows [ADR-0003](0003-elistan-holds-reins-typespec-toolkit.md): the
algorithm (recognise → represent → compose → apply) is elistan's; the type
operations (`op-and` ∩, complement, `op-diff` −, `simplify-or` ∪, range
arithmetic, guard-type lookup) are typespec primitives.

## Composition, and the disjunctive approximation

- `(not c)` swaps `P`/`N`.
- `(and c1 c2)`: the true branch is precise (intersect each variable's `P`); the
  false branch is disjunctive (`¬c1 ∨ ¬c2`).
- `(or c1 c2)`: the false branch is precise (intersect each `N`); the true branch
  is disjunctive.

A single environment per branch cannot represent the disjunctive side precisely
(that needs path-sensitivity — a set of environments). Per the robustness
posture ([ADR-0004](0004-robustness-posture.md)), the **disjunctive branches
(and-false, or-true) are widened to no-op** — the environment is left unchanged.
Sound and simple; it only forgoes some dead-branch findings rather than risking
false positives.

## Recognisers and v1 scope

- Recognisers live in a **registry** (condition shape → refinement builder),
  extended by adding an entry: guard predicates, `eq`/`eql`/`equal`-to-const,
  comparisons → ranges, `memq`/`member`, `null`/`not`, and `and`/`or`/`not`
  composition.
- v1 narrows **direct variable references only** — a condition shaped
  `(op VAR CONST)` / `(op CONST VAR)`, one variable operand and one constant.
- Deferred: multi-variable relations (`(< x y)`) and access-path / occurrence
  typing (`(stringp (car x))`).
