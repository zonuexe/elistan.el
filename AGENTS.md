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

The v1 checker front-end is implemented. Design rationale lives in
`docs/adr/0001`–`0014` and `.scratch/checker-frontend/PRD.md`; the glossary is
`CONTEXT.md`. Modules (each with `*-test.el`):

- `elistan.el` — the type environment (`elistan-env-make/get/set/narrow/join`;
  `var -> type`, functional, default `unknown`).
- `elistan-type.el` — gradual type-op facade over typespec: `consistent-p`
  (disjointness = the only thing flagged), `meet`/`diff`/`union`, `never-p`,
  nil-ness predicates. **The gradual-dynamic layer destined for typespec lives
  here** (see "Coordination" below).
- `elistan-source.el` — function symbol → funspec: user `typespec` declaration,
  then `typespec-builtins-lookup`, then `elistan-source--fallback` (an
  elistan-local coverage table, also destined for typespec).
- `elistan-recognise.el` — condition → refinement (`var -> (true . false)`):
  guards, `null`/`not`, `eq`-to-const, comparisons, `memq`, and `and`/`or`/`not`
  composition; `elistan-refine-true`/`-false` apply it.
- `elistan-finding.el` — `cl-defstruct elistan-finding` + formatter.
- `elistan-walk.el` — the analysis core: `elistan-walk-type` threads
  `(TYPE . ENV)` through special forms with divergence-aware confluence;
  `elistan-walk-defun` / `elistan-check-forms` are the entry points. Three
  findings: `call-type-mismatch`, `dead-branch`, `return-type-mismatch`.
- `elistan-elsa.el` — reads Elsa-style `;; (NAME :: TYPE)` annotation comments
  as an in-file type source, and (opt-in) loads Elsa's `elsa-typed-*.el` builtin
  type databases for coverage; translates Elsa notation to typespec. Drivers bind
  in-file annotations to `elistan-source-local`.
- `elistan-struct.el` — reads `cl-defstruct`/`defclass` definitions as a type
  source: predicate guards (narrowing), constructor/copier/accessor types; the
  class name is an opaque atomic type (full EIEIO subtyping is future work).
- `elistan-batch.el` — batch/CLI driver (`elistan-batch-run`).
- `elistan-project.el` — project-wide (cross-file) checking
  (`elistan-project-check`/`-run`): aggregate every file's annotations + struct
  defs into one registry, so a contract declared in one file checks calls in
  another.
- `elistan-flymake.el` — Flymake backend (`elistan-flymake-setup`).

### Coordination with typespec (implemented locally for now, to migrate)

Per the project plan, type-level logic destined for typespec is implemented in
elistan first and funnelled for later extraction:

- **Gradual dynamic** — typespec treats `unknown` as a top type only on the
  expected side; elistan needs it consistent both ways. Handled in
  `elistan-type.el` (and there is a sibling typespec task to make `unknown` a
  symmetric dynamic).
- **noreturn `never`** — `error`/`signal`/`throw`/… should carry return type
  `never` in the type source; elistan ships a fallback set until typespec does.
- **Promotions** — typespec's internal `typespec-eval-call--type-compatible-p`
  and `typespec-eval-call--split-argspecs` should become public; elistan
  reimplements the small parts it needs (`elistan-source-arglist`).

### Known limitation

elistan reads forms but does not evaluate them. In-file **Elsa-style**
annotations (`;; (NAME :: TYPE)`) *are* read statically (`elistan-elsa.el`), but
`declare`-based typespec declarations in the analysed file are still not
auto-registered. Other function types come from already-loaded declarations,
typespec builtins, and the fallback. Static extraction of in-file `declare`
typespecs is future work.

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
