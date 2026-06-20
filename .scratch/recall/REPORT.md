# elistan quality measurement — recall

elistan's *precision* is established: the full elpa sweep (743 files) reports 20
findings, **0 false positives** (every one verified genuine). This measures the
other axis — **recall**: of the type bugs within the checker's design, how many
does it actually catch? And where is the design boundary?

## Method

`.scratch/recall/recall.el` runs a labelled corpus of self-contained snippets
through the full batch pipeline (`elistan-batch-check-file`: Elsa annotations +
`cl-defstruct`/`defclass` + `(typespec …)`/`declare` + the check). Each case is
labelled `:scope in|out` (within the design, or deliberately out — ADR-0014
etc.) and `:expect CATEGORY|nil`.

Reproduce:

```sh
emacs -Q --batch -L . -L ../emacs-typespec -l .scratch/recall/recall.el
```

## Result

```
In-scope recall : 14/14 caught (100%)
Precision (correct cases): 0 false positives
Out-of-scope leaks       : 0/6 emitted a finding
```

(Was 11/12 until `and`/`or` constant-guard detection landed; see
`MACROEXPAND-LEAK.md` for the determinism fix that made that feature safe.
`dead/else-subtype` is the false-branch direction of guard narrowing —
`(arrayp x)` on a `string` makes the guard always-true, so the else branch is
dead — unlocked by typespec's sound strict subtype relation.  `slot/setf-oref`
is the idiomatic `(setf (oref …) …)` slot write, checked once the walker loads
eieio so setf expands to `eieio-oset`.)

- **In-scope recall 92%** across all four finding categories
  (call-type-mismatch, dead-branch, return-type-mismatch, slot-type-mismatch),
  including bugs *inside lambda bodies* and against every contract source
  (Elsa `::`, `(typespec …)` macro, `declare typespec-ftype`).
- **Precision held**: the correct-code cases (including a subclass passed where
  a superclass is wanted) produced **0** findings.
- **0 out-of-scope leaks**: the six deliberately-out-of-scope bugs all stayed
  silent — no accidental findings outside the design.

## What the measurement found (and fixed)

The first run was **8/12 (67%)**. Three of the four "misses" were not detection
failures — the checker *detected* the call-type-mismatch but the finding had a
**nil source position** (the buggy argument was a literal `5` / `"x"`, and
`read-positioning-symbols` does not position numbers/strings), so the batch
driver dropped it as "position-less / not user-actionable".

Fix (`elistan-walk--check-args`): fall back to the call's function-symbol
position when a literal argument has none. Recall → **11/12 (92%)**; the elpa
sweep is unchanged (743/20/0 — in-file authoritative contracts, which
argument-checking requires, are rare in elpa, but real annotated projects now
get these reports).

## The design ceiling (expected misses, by design)

These are **not** bugs in the checker — they are the deliberate zero-FP scope
(ADR-0002/0004/0014):

| Miss | Why out of scope |
|---|---|
| `(+ "a" 1)`, `(length 5)` | builtins are leniently polymorphic; only author-written contracts are arg-checked |
| inter-procedural (`(1+ (producer))`, untyped `producer`) | no whole-program inference; an untyped function returns `unknown` |
| free/special-var flow (`(setq gv 5) … (need-str gv)`) | only lexical vars are tracked through `setq` |
| `(car xs)` element type, `(car (if x nil 1))` | container element types / nil-safety are not modelled |

These quantify the ceiling: lifting any of them trades against the zero-FP
guarantee or needs whole-program inference — out of the v1 design.

## Remaining in-scope gap (one genuine miss)

`(and (integerp x) x)` with `x : string` — `(integerp x)` is a provably-false
guard, but dead-branch detection only fires on `if`/`cond` *branches*, not on a
guard in `and`/`or` operand position. A possible future enhancement: flag a
provably-constant guard wherever it appears. Low priority (uncommon; and the
`and` already types as `null` downstream).

## Takeaway

Within its design the checker has **high recall (100%) at zero false positives**.
The measurement more than paid for itself — it surfaced three real bugs that the
synthetic corpus and prior human verification had missed:

1. **Literal-argument position drop** — a detected call mismatch was discarded
   for lack of a source position (fixed: fall back to the call's function pos).
2. **Order-dependent inference** — `macroexpand-all` applied load-order-dependent
   compiler-macros, making analysis non-reproducible (fixed: deterministic
   `elistan-walk--macroexpand`). See `MACROEXPAND-LEAK.md`.
3. **A latent false positive in the baseline** — Elsa's DB typed
   `help-function-arglist` as never returning a string, so
   `(stringp (help-function-arglist f))` at `marginalia.el:619` was wrongly
   "dead" (fixed: `elistan-elsa--corrections` overrides unsound DB return
   types). The "20 findings, zero FP" baseline was really 19 TP + 1 FP.
