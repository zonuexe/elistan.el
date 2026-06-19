# Scope relative to Elsa: a focused MVP, expandable later

[Elsa](https://github.com/emacs-elsa/Elsa) is the mature incumbent Emacs Lisp
static analyser. elistan deliberately ships a **narrow MVP** that differs in
posture and reuses typespec, rather than re-implementing Elsa. These boundaries
are **MVP scope cuts, not permanent exclusions** — expansion is anticipated and
likely.

## Positioning vs Elsa

- Elsa owns its own type system and runs **whole-project**: cross-file state,
  inference, dependency layering, caching, an LSP server, a broad style-lint
  ruleset, and rich builtin/library type databases (dash, seq, cl, eieio).
- elistan is **lighter and quieter**: type meaning delegated to **typespec**
  (ADR-0003); **per-defun, declared-only** analysis (ADR-0002); a **gradual,
  zero-false-positive** posture (ADR-0004); **editor-first / incremental**
  (ADR-0008). It aims to *complement* Elsa, not replace it.

## Out of MVP scope (expandable)

- **Style / lint rules** (Elsa's progn-unwrapping, `if`→`when`, eta-reduction,
  naming, docstring presence, `error` message format). elistan is a type/flow
  checker; these are a different category that Elsa, checkdoc, and package-lint
  already cover. An optional style layer could be added later.
- **Whole-project / cross-file / inference / caching** (ADR-0002) — the most
  deliberate Elsa contrast, and likely the biggest future expansion (cross-file
  type resolution, a project mode).
- **byte-compiler overlap** — unbound variables, argument *count* (arity),
  deprecated functions. Left to the byte-compiler; elistan focuses on argument
  *type* compatibility.

## In MVP scope — including where elistan exceeds Elsa

- The three findings: call-argument type mismatch, dead-branch / provably-constant
  condition, declared-return mismatch.
- **Relational narrowing** — `eq`/`equal`-to-const, comparisons → ranges (using
  typespec's numeric ranges), `memq`/`member` — which Elsa does **not**
  implement. A genuine differentiator, kept in scope (ADR-0009).

## Coverage gap and its planned expansion (S5)

Elsa ships extensive builtin/library type databases; typespec's coverage is
currently far smaller, which caps elistan's real-world reach. **The MVP accepts
the lower coverage.** Anticipated expansion: grow typespec's databases, and/or
read **Elsa-style annotations / Elsa's type databases as a type source** —
already foreseen as a pluggable source in ADR-0002.
