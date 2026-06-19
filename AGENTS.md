# AGENTS.md — elistan

Guidance for an AI agent working in this repo. (`CLAUDE.md` is a symlink to
this file.) Keep it accurate as the project evolves.

## What elistan is

A **flow-sensitive type checker for Emacs Lisp**, built on top of the
[`typespec`](../emacs-typespec) type-operations foundation. elistan is a
*consumer* of typespec.

## Architecture & boundary (read first)

There are two repos with a deliberate split:

- **typespec** (`../emacs-typespec`) owns the *meaning of the type notation*:
  the type algebra (union/intersection/difference/complement), normalization,
  subtyping, type-level evaluation, the guard/assert **narrowing effect**, and
  typespec resolution. It is a pure type-operations library. It does **not**
  walk Emacs Lisp source — that is an explicit non-goal there.
- **elistan** (this repo) owns the *orchestration over code*: a type
  environment, threading types through control flow, recognizing conditions,
  and reporting. Walking/analyzing real code **is** elistan's job.

Litmus when deciding where code goes: *a pure function of types/values* →
typespec; *walks or drives a program* → elistan. If you need a new pure type
operation (e.g. a new normalization or a condition-narrowing rule that is a
function of types only), prefer adding it in typespec and consuming it here —
coordinate the boundary rather than reimplementing type algebra in elistan.

## Dependency on typespec

- typespec sources live at `../emacs-typespec` (sibling). `make check` adds it
  to `load-path` (`-L ../emacs-typespec`) and loads the **source** (not an
  installed package). Override the path: `make check TYPESPEC=/path/to/typespec`.
- Require it with `(require 'typespec-eval)`.

### Foundation API elistan consumes

- `(typespec-eval FORM)` — evaluate/normalize a typespec form to a canonical
  type (constant folding, range arithmetic, simplification).
- `(typespec-eval-call FUNSPEC ARG-TYPES)` — type a function application;
  returns the result type or `(:cause-error INFO)`.
- `(typespec-eval-call-narrowing FUNSPEC ARG-TYPES)` — the guard/assert
  refinement effect on the **first positional argument**:
  `(:index 0 :true T :false T)` for `:guard`/`:guard!`, `(:index 0 :assert T)`
  for `:assert`, or nil. This is what `elistan-env-narrow` is built on.
- Type algebra: `(typespec-eval-simplify-or ITEMS)` (union),
  `(typespec-eval-op-and ITEMS)` (intersection),
  `(typespec-eval-op-diff LHS RHS)` (difference).
- Subtyping: `(typespec-eval-types-type-subtype-p SUB SUPER)`. Note the precise
  call-compatibility check `typespec-eval-call--type-compatible-p` is `--`
  internal to typespec; if you need it as public API, promote it in typespec
  rather than copying it.
- Resolving a function's declared type:
  `(function-get SYM 'typespec)` returns a **record** plist; the spec is
  `(plist-get (function-get SYM 'typespec) :spec)`.
- Mapping a predicate form to a guard type (for condition recognition):
  `typespec-eval-types-type-predicate-name` (symbol → predicate fn) and
  `typespec-eval-types-get-guard-return-type` (predicate → its guard type).

Docs in typespec worth reading: `typespec.md` (notation),
`type-level-evaluation.md` (guards / conditional return / narrowing),
`conformance.md` (exactly what the evaluator implements, and known gaps).

## Type representation

S-expression typespec forms, e.g. `string`, `(or string integer)`,
`(integer 0 10)`, `(const x)`, `(:tuple A B)`, `(function (A) R)`. Not CLOS
objects. Use the foundation functions above to operate on them.

## Current state

`elistan.el` — the flow-sensitivity layer only:

- `elistan-env-make` / `elistan-env-get` / `elistan-env-set` — a type
  environment (`var -> type`, functional; default `unknown`).
- `elistan-env-narrow ENV VAR FUNSPEC` — apply a guard tested on VAR; returns
  `(:true ENV :false ENV)` or `(:assert ENV)`.
- `elistan-env-join ENV-A ENV-B` — union each variable's type at a confluence.

`elistan-test.el` covers these. That is the entire implementation so far.

## Roadmap — the checker front-end (next work)

Drive the environment over code:

1. Walk forms: `if`/`cond`/`when`/`unless`/`and`/`or`/`let`/`let*`/`progn`/…
2. At a condition, identify the tested variable and predicate, resolve the
   predicate's typespec (`function-get` → `:spec`), and call
   `elistan-env-narrow` to get the per-branch environments.
3. Type each branch under its environment (`typespec-eval` /
   `typespec-eval-call` for expression/return types).
4. `elistan-env-join` at confluences.
5. Beyond guard predicates, add narrowing for `eq`/`eql`/`equal` to a const,
   comparisons → ranges, `memq`/`member`, `null`/`not`, and `and`/`or`/`not`
   condition composition. Decide per case whether the *type-level* rule belongs
   in typespec (pure, reusable) and only the recognition/driving here.

**Open design question:** how elistan obtains forms to analyze. typespec does
not parse Lisp; elistan decides its own input (macro-expanded source, an
already-read AST, etc.). The current narrowing is first-positional-argument
centric (per the guard spec); relational conditions need their own var
identification.

## Conventions

- Emacs 29.1+, `lexical-binding: t`.
- Public prefix `elistan-`; internal `elistan--`.
- GPL-3.0-or-later; Author: USAMI Kenta <tadsan@zonu.me>.
- Tests use `ert`. Match the surrounding Elisp style (see typespec for the
  house style: small focused defuns, docstrings, `pcase`).

## Commands

- `make check` — clean → run tests (source) → byte-compile → run tests
  (compiled). Requires `../emacs-typespec`.
- `make test-source` / `make compile` / `make clean`.

## Gotchas

- `make check` loads typespec **source**. If `../emacs-typespec` has stale
  `.elc` files they can shadow the source — run `(cd ../emacs-typespec && make clean)`.
- No git remote is configured yet for this repo.

## Agent skills

Configuration the engineering skills read from. See `docs/agents/` for details.

### Issue tracker

Issues and PRDs live as local markdown files under `.scratch/<feature>/` (this
repo has no remote). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root (created lazily
by the skills, not now). See `docs/agents/domain.md`.
