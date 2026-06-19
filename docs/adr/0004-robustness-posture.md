# Robustness posture: report only provable incompatibilities; v1 is intentionally unsound

Adapting Rigor's ADR-5 robustness principle (Postel's law) to a *checker* that
consumes — rather than authors — signatures, elistan's governing posture is:
**emit a finding only when an incompatibility is provable; when the relevant
type is the gradual dynamic (`unknown`) or otherwise partial, accept it and stay
silent.** The top priority is **zero false positives**, even at the cost of
false negatives — v1 is deliberately *unsound*.

## Why

- Use case A (in-buffer, [ADR-0001](0001-pure-analysis-core-and-drivers.md))
  makes false positives especially costly: a noisy checker trains users to
  ignore it, or to paste workarounds (Rigor's "workaround-multiplication
  anti-pattern").
- The two halves of Postel's law map onto a checker as: *be liberal in what you
  accept* → conservative finding emission (this posture); *be conservative in
  what you produce* → propagate the **most precise type the checker can prove**,
  so downstream narrowing keeps biting.
- The authoring asymmetry (strict-return / lenient-param) is **not** elistan's —
  it belongs to whoever authors signatures, i.e. the type sources / typespec
  ([ADR-0003](0003-elistan-holds-reins-typespec-toolkit.md)).

## Consequences

- The acceptance test is gradual **consistency**, not strict subtyping; the
  gradual dynamic (`unknown`) is accepted in both directions — this depends on
  the typespec dynamic from ADR-0003.
- Soundness is explicitly a non-goal for v1. "Why didn't elistan catch this?" is
  an accepted outcome whenever the relevant types were not provably
  incompatible.

(Derived from Rigor ADR-5,
<https://rigor.typedduck.fail/adr/5-robustness-principle>, same author;
CC BY-SA 4.0.)
