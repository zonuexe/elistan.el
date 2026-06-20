# PRD — elistan checker front-end (v1 design sketch)

Status: v1 implemented. Modules `elistan-{type,source,recognise,finding,walk,batch,flymake}.el`
(+ the `elistan.el` env layer), all green under `make check`. See `docs/adr/0001`–`0013`.

## Goal

Build the front-end that drives the existing flow-sensitivity layer
(`elistan-env-*`) over real code: walk forms, recognise conditions, narrow, type
expressions and calls, join at confluences, and emit findings.

## Architecture (decided — see ADRs)

- Pure **analysis core** (already-read forms → findings) + thin **drivers**
  (batch driver for CLI/CI, editor driver for in-buffer) — ADR-0001.
- Function types come from pluggable **type sources**; v1 wires only the
  **declared typespec** source; no local inference — ADR-0002.
- **elistan holds the reins**; **typespec** is a low-level type-operations
  toolkit + helpers, one source among several; the gradual **dynamic**
  (`unknown`) is a first-class typespec type, distinct from top (`mixed`) —
  ADR-0003.
- **Robustness posture**: report only provable incompatibilities; uncertain or
  dynamic ⇒ accept; v1 is intentionally unsound for zero false positives —
  ADR-0004.
- **Macro handling**: special forms interpreted natively; macros expanded by
  default (short-circuit list empty in v1); positions via `symbols-with-pos` —
  ADR-0005.
- **Finding record**: structured `cl-defstruct` (category + location + severity
  + per-category data); rendering done by a separate formatter — ADR-0006.
- **Parameter entry types**: seeded positionally from the defun's own declared
  funspec, honored as written (no `&optional` null-widening); else `unknown` —
  ADR-0007.
- **Editor driver acquisition**: per-top-level-form unit (incremental by
  construction); unreadable forms skipped silently; v1 analyses function-defining
  forms only — ADR-0008.
- **Narrowing representation**: per-variable refinements (`var → (:true P
  :false N)`) composed by type algebra; disjunctive branches widened; recogniser
  registry; v1 narrows direct variables only — ADR-0009.
- **Walker threading**: `type-expr → (:type :env)` (mutation) + `recognise →
  refinement` (condition); divergence-aware confluence (`never` branches excluded
  → guard-clause narrowing) — ADR-0010.
- **Mutation & loops**: `setq` rebinds tracked vars (clears narrowing); loops
  widen body-assigned vars to `unknown` (no fixpoint in v1) — ADR-0011.
- **Return-type check**: body tail value vs declared return by gradual
  consistency (category 3); early returns approximated — ADR-0012.
- **Scope vs Elsa**: intentional MVP — lighter/quieter than Elsa (per-defun,
  gradual, typespec-backed); style-lint, project-wide analysis, and
  byte-compiler overlap are out of MVP scope; relational narrowing is a kept
  differentiator; expansion anticipated — ADR-0013.

## v1 finding scope

v1 emits exactly these three:

1. **Provable call incompatibility** — an argument's type is provably
   incompatible with the called function's declared parameter type
   (`typespec-eval-call` → `:cause-error`, once the dynamic fix lands).
   Evaluated per argument so one bad arg doesn't suppress the rest.
2. **Provably-constant condition / unreachable branch** — flow shows a tested
   condition is always-true or always-false (e.g. testing `(integerp x)` where
   `x : string`), so a branch is dead.
3. **Return-type mismatch** — only for a defun that *declared* a return type,
   when the body's type is provably incompatible with it.

Everything else (nil-safety beyond calls, arity-only checks, …) is out of v1
unless it reduces to (1).

## Dependencies / open

- **typespec (blocking (1)):** `unknown` must become the gradual dynamic —
  both-direction consistent, and `typespec-eval-call` must not `:cause-error`
  on an `unknown` argument. Tracked as a typespec-side task.
- **Deferred / future:** changed-only incremental re-analysis (optimisation);
  `&key`/keyword (`cl-defun`) parameters; analysing non-function top-level forms;
  a Flycheck backend; the batch driver's CLI surface; precise
  `catch`/`condition-case` modelling. **Elsa-contrast expansions (ADR-0013):** a
  project / cross-file mode; reading Elsa builtin *type databases* as a source
  (Elsa annotation *comments* are done — `elistan-elsa.el`); an optional
  style-lint layer.
- **typespec helper promotions (coordination):** make `--type-compatible-p` (the
  gradual-consistency check) and `--split-argspecs` public, per ADR-0003.
- **noreturn `never` specs (coordination):** noreturn functions (`error`,
  `signal`, `throw`, `user-error`, `cl-return*`, …) need return type `never` in
  the type source for data-driven divergence (ADR-0010). v1 uses a built-in
  fallback set until then.
- **typespec range-intersection bug (coordination):** intersecting two
  half-bounded integer ranges errors — `(typespec-eval-op-and '((integer * 5)
  (integer 3 *)))` raises `wrong-type-argument number-or-marker-p *`. elistan's
  type facade guards every typespec call with a conservative fallback so the
  checker cannot crash, but the foundation bug should be fixed upstream.
- **typespec `(const nil)` / `boolean` intersection bug (coordination):**
  `meet` of `(const nil)` (or `boolean`) with a type that contains nil yields
  `never` instead of `(const nil)`/`null`, and `boolean - (const t)` does not
  simplify to `null`. elistan works around it by narrowing `(eq x nil)` with the
  `null` type and spelling Elsa `bool` as `(or (const t) null)`; the foundation
  should handle nil constants in range/boolean intersection.
- **`let`/`let*`/`lambda`** scoping is handled mechanically by the threading
  model (typed inits, sequential `let*`, shadowing); not separately grilled.
  (Lambda *bodies* are not yet descended into — deferred.)
- **Known limitation:** forms are read, not evaluated, so `declare`-based
  typespec declarations in the analysed file are not auto-registered. Static
  extraction of in-file declarations is future work.

## Walk targets (from AGENTS.md roadmap)

`if` / `cond` / `when` / `unless` / `and` / `or` / `not` / `let` / `let*` /
`progn`; condition recognition starting with guard predicates, then extending to
`eq`/`eql`/`equal`-to-const, comparisons → ranges, `memq`/`member`, `null`/`not`,
and boolean composition.
