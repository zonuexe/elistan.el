# Walker: mutation (setq) and loops widen rather than iterate

## Mutation

`(setq v e)` types `e`, rebinds `v` to the value type in the environment, and
yields that type. Reassignment **discards any prior narrowing** of `v`. Only
environment-tracked variables (lexical bindings and parameters) are updated;
`setq` to a global/special variable, and `setf` to a non-variable place
(`(setf (car x) v)`), do not refine a variable's type — it stays as it was.
`push`/`pop`/`cl-incf`/`setf` are macros that expand to `setq`/primitives
([ADR-0005](0005-macro-handling.md)), so they need no special handling. Mutation
inside a branch is carried by each branch's out-env and merged by the
divergence-aware join ([ADR-0010](0010-walker-threading-and-divergence.md)).

## Loops

A `while` body runs 0..n times, so a variable assigned in the body has a type
that is a fixpoint across iterations. v1 does **not** iterate to a fixpoint.
Instead it widens: the variables **assigned anywhere in the loop body** are set
to `unknown` at the loop head and after the loop.

Rejected alternatives:

- **Fixpoint + widening operators** — precise but complex (ranges can grow
  without bound, requiring widening to terminate). Deferred.
- **Single body pass, then join** — precise for fresh-reassign loops (`dolist`)
  but *underestimates* accumulators (`(setq acc (cons v acc))`), and an
  underestimate can manufacture a false dead-branch — a false positive, which the
  robustness posture ([ADR-0004](0004-robustness-posture.md)) forbids.

Widening to `unknown` is an over-estimate: sound, terminating, and
false-positive-free. The cost is precision on loop-carried variables (notably the
`dolist`/`dotimes` loop variable, since those expand to `while` + `setq`).
Recovering it (a `dolist` special case, or a bounded fixpoint) is deferred.

Within the body, the loop `test`'s refinement still narrows variables **not**
assigned in the body; after the loop, the test's false-refinement applies.
