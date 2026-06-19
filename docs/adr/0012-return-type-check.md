# Return-type check (finding category 3): tail value vs declared return; early returns approximated

The body value type of a defun is the value type of its **tail form** (the
implicit `progn`'s last form) — already divergence-aware, and already a union
when the tail is an `if`/`cond` ([ADR-0010](0010-walker-threading-and-divergence.md)).

When — and only when — the defun **declares a return type**
([ADR-0002](0002-declared-typespec-only-v1.md), [ADR-0007](0007-parameter-entry-types.md)),
the body value type is checked against it by gradual consistency
([ADR-0004](0004-robustness-posture.md)): a provable incompatibility raises a
`return-type-mismatch` finding (category 3), located at the tail form
([ADR-0006](0006-finding-record.md)).

- A body value type of `unknown` (dynamic) is consistent with any declared
  return → no finding.
- A body that is `never` (wholly diverging) is vacuously consistent with any
  declared return → no finding.
- No declared return type → no category-3 finding (v1 does not infer returns).

## Early returns are approximated

`cl-return-from` / `cl-block` / `cl-return` / `throw`-based early exits add their
values to the function's true return type (precisely, the union over all return
points). As with the `catch`/`condition-case` approximation in ADR-0010, **v1
checks the tail value only**; early-return values in functions using a
block/return construct go unchecked (a false negative, acceptable under the
robustness posture). Collecting all return points (return-point tracking, akin to
catch-tag tracking) is deferred.
