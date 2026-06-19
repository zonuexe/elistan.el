# elistan holds the reins; typespec is a low-level type toolkit, one source among many

elistan (like Rigor) is the static analyzer and holds **all** the reins: it
walks the code, threads the type environment, decides analysis policy (what "no
information" means, what counts as acceptable, when to emit a finding), and
resolves where a function's type comes from.

A function's type can come from several **type sources**, and typespec is only
one of them — analogous to how RBS is one of Rigor's sources:

- a declared typespec (`function-get` → `:spec`),
- Emacs built-in type knowledge,
- Elsa-style comment type annotations,
- types obtained directly from inference.

**typespec** is not the analyzer and does not own analysis policy. It provides a
**low-level API for operating on types** (the algebra, subtyping, gradual
consistency, narrowing computation, normalization) plus **helpers** that make
building a consumer easier. It *processes* whatever types the sources yield; it
does not decide which source wins or what counts as an error.

## Consequences

- Policy lives in elistan: which relation to check arguments with, the meaning
  of the "no information" default, and the decision to emit a finding are all
  elistan's.
- typespec must expose its **relations as primitives** — strict subtyping *and*
  a gradual-consistency check — without baking the choice into one high-level
  call. `typespec-eval-call` is a convenience helper whose "unknown argument ⇒
  `:cause-error`" behaviour is *one* policy; elistan is free to drive
  lower-level operations instead of inheriting it.
- [ADR-0002](0002-declared-typespec-only-v1.md) is reframed: **type source is a
  pluggable abstraction**; v1 merely wires the typespec source. The built-in DB,
  Elsa comments, and inference are future sources behind the same seam.
- Inference is an elistan-side concern (a type source), not a typespec feature;
  typespec only processes inferred types.

## Resolved: the gradual dynamic is a first-class type, owned by typespec

The **dynamic** ("we don't know — treat as compatible") and the **top** type
(the supertype of all values) are *separate concepts*, and the distinction is
given to typespec's type system. elistan's "no information" default **is** the
gradual dynamic, spelled `unknown`; elistan keeps `unknown` as its default and
relies on typespec treating it as consistent in **both** directions — so an
`unknown` argument is accepted, never a `:cause-error`. Top stays spelled
`mixed`. The seam then disappears: elistan's default and typespec's dynamic are
the same concept.

**typespec-side requirement (coordination):** `unknown` must be the gradual
dynamic (both-direction consistency); `typespec-eval-call` must not report
`(:cause-error …)` for an `unknown` argument; and `unknown` (dynamic) must stay
distinct from `mixed` (top). To be recorded as a typespec ADR. The seam is real
today: `typespec-eval-call` currently returns `(:cause-error …)` for an
`unknown` argument, and `mixed`/`t` — not `unknown` — are what its compatibility
check accepts in both directions.

(Derived from the positioning of [Rigor](https://rigor.typedduck.fail) and its
ADR-5 robustness principle, same author.)
