# elistan — current work / handoff

Handoff for the next session. elistan is a **flow-sensitive type checker for
Emacs Lisp** built on the sibling `typespec` library (`../emacs-typespec`).
Read `AGENTS.md` first (architecture + module map), then `CONTEXT.md` (glossary)
and `docs/adr/0001`–`0014` (design decisions). v1 scope lives in
`.scratch/checker-frontend/PRD.md`.

## Status

The v1 checker front-end is **implemented, hardened on real codebases, and
extended** with project-wide checking and a defstruct/defclass type source.

- Branch: **`master`** (local repo, no remote). Working tree clean; everything
  committed. (There is no `main`; `master` is the default.)
- **66 ert tests**, green on source *and* byte-compiled (`make check`).
- 12 source modules + 12 `*-test.el`.

## Build / test / run

```sh
make check          # clean -> test (source) -> byte-compile -> test (.elc)
make test-source    # tests against source only (fast iteration)
```

Requires `../emacs-typespec`. **Gotcha:** stale `.elc` shadow source — if an
ad-hoc `emacs --batch` run prints "newer than byte-compiled file; using older
file", run `make clean` first. Same applies to `../emacs-typespec`.

Run the checker:

```sh
# batch / CLI (one or more files)
emacs -Q --batch -L . -L ../emacs-typespec -l elistan-batch \
  --eval '(elistan-batch-run)' FILE.el ...
# project-wide (cross-file contracts)
emacs -Q --batch -L . -L ../emacs-typespec -l elistan-project \
  --eval '(elistan-project-run)' FILE.el ...
# editor: (add-hook 'emacs-lisp-mode-hook #'elistan-flymake-setup)
```

## Module map (each has a `*-test.el`)

- `elistan.el` — type environment (`elistan-env-make/get/set/narrow/join`).
- `elistan-type.el` — gradual type-op facade over typespec. **`consistent-p`
  = disjointness only** (the zero-FP relation). Guards every typespec call
  (typespec can error/blow up); a **type-size cap** collapses oversized types to
  `unknown`. The gradual-dynamic layer destined for typespec lives here.
- `elistan-source.el` — function symbol → funspec. Resolution order:
  `elistan-source-local` (in-file, highest) → user `typespec` decl →
  `typespec-builtins-lookup` → `elistan-source-builtins` (loaded DBs) →
  `elistan-source--fallback`. `elistan-source-authoritative-p` = only in-file
  annotations + user decls are trusted for **argument checking** (ADR-0014).
- `elistan-elsa.el` — reads Elsa `;; (NAME :: TYPE)` annotations *and* Elsa's
  `elsa-typed-*.el` builtin DBs (`elistan-elsa-register-typed-dbs`, opt-in,
  ~327 types). Translates Elsa notation → typespec.
- `elistan-struct.el` — reads `cl-defstruct`/`defclass` as a type source
  (predicate guards, constructor/copier/accessor/`:reader` types). Instances are
  typed `(:class NAME)` and the class hierarchy (`:include` / defclass parents)
  is supplied to typespec's static subtyping via
  `elistan-struct-parse-hierarchy`; inherited `:include` slot accessors are
  registered (same-buffer). Slot `:type` becomes the reader return type
  (`elistan-struct--translate-type`, conservative: unmodelled → `mixed`,
  parameterised containers → bare container); a nil/absent default widens it
  with `null` so a `cl-defstruct` `:type` that the nil default contradicts
  can't be misread as never-nil. Honours the `:copier` option name.
- `elistan-declare.el` — reads the analysed file's own typespec declarations:
  the `(typespec #'NAME SPEC)` macro and `(declare (typespec-ftype SPEC))` defun
  forms. Bound into `elistan-source-local`, so an in-file contract is
  authoritative (hardened against improper/dotted forms).
- `elistan-recognise.el` — condition → refinement (guards, null/not, eq-const,
  comparisons, memq, and/or/not).
- `elistan-finding.el` — `cl-defstruct elistan-finding` + formatter.
- `elistan-walk.el` — the analysis core. `elistan-walk-type` threads
  `(TYPE . ENV)` with divergence-aware confluence; `elistan-walk-defun` /
  `elistan-check-forms` are the entry points. Descends into lambda bodies
  (params + captured vars `unknown`). **Per-defun work budget** +
  symbols-with-pos. Three findings: `call-type-mismatch`, `dead-branch`,
  `return-type-mismatch`.
- `elistan-batch.el` — batch/CLI driver; merges in-file annotations + struct
  defs + typespec declarations into `elistan-source-local`; drops findings with
  no position.
- `elistan-project.el` — project-wide (cross-file) checking.
- `elistan-flymake.el` — Flymake backend (now merges the same in-file sources
  as the batch driver).

## Posture (important)

**Zero false positives** (ADR-0004): emit a finding only on a *provable*
incompatibility; uncertain/`unknown` ⇒ accept. Over-approximation is always
safe. When adding features, verify any new finding on real code is a true
positive — this is the project's defining constraint. Key derived rules:
- Argument mismatches fire only against author-written contracts, never builtin
  databases (Emacs builtins are leniently polymorphic — `(message nil)` is
  valid). Builtins still drive narrowing + result typing. (ADR-0014)
- Only **lexical** variables are tracked through `setq`; free/special vars stay
  `unknown`. A `let`-binding to literal `nil` is seeded `unknown`.

## Validation

Swept Elsa + the full elpa set (`~/.emacs.d/elpa`) with Elsa's builtin DBs
loaded: **743 files → 20 findings, 0 crashes, ~6s** (corpus drifts as packages
update). Every finding verified to be genuine dead code (zero false positives).
The count grew from the v1 baseline of 19 via: lambda-body descent (+1 genuine,
and its `setq` soundness fix −1 pre-existing FP) and the typespec `(const nil)`
intersection fix (+1 genuine — a redundant `(eq type 'year)` inside a pcase
`year` arm in datetime.el). Reproduce:

```elisp
;; emacs -Q --batch -L . -L ../emacs-typespec -l elistan-batch --eval '(...)'
(elistan-elsa-register-typed-dbs
 (file-expand-wildcards "/Users/megurine/repo/emacs/Elsa/elsa-typed-*.el"))
(dolist (d (file-expand-wildcards "~/.emacs.d/elpa/*/"))
  (dolist (f (directory-files d t "\\.el\\'"))
    (unless (string-match-p "-autoloads\\|-pkg\\|-tests?\\.el" f)
      (condition-case e (elistan-batch-check-file f) (error ...)))))
```

Real test corpora: `/Users/megurine/repo/emacs/Elsa` (annotations + builtin DBs)
and `~/.emacs.d/elpa` (202 packages). The hardening pass fixed: 2 crash classes
(improper/dotted lists, `macroexpand-all` failure e.g. `named-let`), 1 hang
(huge generated form / circular literal — bounded by the work budget + type-size
cap), and ~9 false-positive classes (`never`-value, and/or & condition-case
`setq` carry, nil-binding accumulators, lexical-only tracking, `(quote nil)`,
`(const nil)` quirks, too-strict builtin arg checking).

## typespec coordination items (work belongs upstream)

Status after the `../emacs-typespec` foundation pass:
1. ~~**Gradual dynamic**~~ — *done upstream* (typespec ADR-0001; `unknown` is the
   symmetric gradual dynamic, `typespec-eval-call` no longer `:cause-error`s on
   an `unknown` argument).
2. ~~**Range intersection bug**~~ — *done upstream* (`(and (integer * 5)
   (integer 3 *))` ≡ `(integer 3 5)`).
3. ~~**`(const nil)` / `boolean` intersection**~~ — *done upstream*
   (typespec `1971f15`, `89d19ce`): `(const V)` intersects/differences by
   membership, and finite `boolean` differences reduce. elistan's
   `(or (const t) null)` spelling for `boolean` was reverted to plain `boolean`
   (`4ac7dd1`).
4. ~~**noreturn `never`**~~ — *done upstream* (`ba3e471`): the noreturn builtins
   are registered in `typespec-builtins` with a `never' return. elistan's
   fallback was trimmed to just the `cl-return*` macros (`bb…`/source commit).
5. ~~**Promote internals to public API**~~ — *done upstream* (`ba3e471`):
   `typespec-eval-call-split-argspecs` and `typespec-eval-call-type-compatible-p`
   are now public wrappers. (elistan has not yet adopted them — see EIEIO step 2
   / a future DRY pass for `elistan-source-arglist`.)
6. ~~**Class types — static subtyping (foundation)**~~ — *done upstream*
   (`6e393ba`): `(:class C)` ⊑ `(:class P)` is decided statically from a
   supplied `typespec-eval-types-class-parents` hierarchy; meet narrows to the
   subclass; unrelated classes stay non-disjoint (zero-FP, sound under EIEIO's
   open world). **elistan does not emit `(:class)` yet** — wiring it up is the
   next EIEIO increment (see below).

## Deferred / next steps (rough feasibility order)

1. ~~**Slot `:type` precision**~~ — *done.* `elistan-struct.el` reads
   `cl-defstruct`/`defclass` slot `:type` and translates it to the accessor
   return type (conservative whitelist; nil-default widening keeps zero FP).
   Re-validated on the full elpa sweep (still 19 findings / 0 crashes).
   Parameterised containers (`(list-of T)`, `(vector T N)`, `(array …)`,
   `(string N)`, `(cons …)`) widen to the bare container type (sound).
   *Future precision left here:* element types inside those containers, and
   chasing a slot whose `:type` is another struct/class (cross-references) —
   the former drops to the container, the latter stays opaque.
2. ~~**Static in-file `declare` typespecs**~~ — *done* (`elistan-declare.el`).
   Reads the analysed file's own `(typespec #'NAME SPEC)` macro and
   `(declare (typespec-ftype SPEC))` forms statically and binds them into
   `elistan-source-local` (authoritative). Wired into batch, project, *and*
   flymake; re-validated on the elpa sweep (19 findings / 0 crashes). Note: the
   canonical form is the `(typespec …)` *macro*, not `(declare (typespec …))`
   (no such declaration handler exists in typespec); `typespec-ftype` is
   typespec's experimental `declare` spec. Only function/`:forall` specs are
   registered.
3. ~~**Lambda body descent**~~ — *done* (`elistan-walk.el`). Lambda bodies are
   walked for findings (params + captured vars `unknown` → zero-FP). This also
   exposed and fixed a latent `setq` soundness bug (reassigning a non-lexical
   var now invalidates its narrowing), removing one pre-existing FP
   (logview.el:3227). Sweep: 743 files / 19 findings / 0 crashes.
4. **Full EIEIO** — foundation + (a)/(b) **done**:
   - ~~(a) emit `(:class NAME)` + supply hierarchy~~ — done (typespec `6e393ba`
     static subtyping; elistan emits `(:class)`, drivers bind
     `typespec-eval-types-class-parents`). Subclass accepted where superclass
     wanted; `(child-p x)` narrows a superclass var to the subclass.
   - ~~(b) inherited `:include` accessors~~ — done (same-buffer resolution).
   - **(c) slot-typed `oref`/`oset`** — *remaining*. `(oref obj slot)` →
     the slot's `:type`; needs a class→slot-type table (and obj's class). The
     generic `oref`/`oset` are less common than named accessors (already typed).
   - **Cross-file inherited accessors** (project mode) — *remaining*: a parent
     in another file currently ends the chain; would need a project-wide
     struct-info pass.
   Design note: under zero-FP + EIEIO's open world, class subtyping adds
   *acceptance/narrowing precision*, not rejection of unrelated classes (that
   would be unsound) — so the additive parts (b)/(c) are where the value is.
5. **Flycheck backend** — postponed by request (needs an optional-dependency
   build decision: flycheck isn't on the `make` load-path).
6. **Lower-value / thorny deferred** (see PRD "Deferred / future"):
   - **non-function top-level forms** — *unsafe naively*: most top-level
     definition macros (`compat-defun`, `cl-defmethod`, `use-package`, …) are
     not loaded during analysis, so `macroexpand-all` leaves them and walking
     them as expressions yields FPs + crashes (verified empirically). A sound
     version must gate on "head is a loaded function", which excludes the
     interesting macro targets — i.e. the safe slice is low value.
   - **`&key`/`cl-defun` params** — elistan only argument-checks against
     authoritative in-file contracts, which essentially never declare typed
     `&key` params today, so low marginal value (typespec *does* support `&key`
     in `typespec-eval-call`, so result typing already benefits).
   - **precise `catch`/`condition-case`** — basic `throw` divergence already
     works via the `never` fallback; the precise tag-matching is low value.
   - **changed-only incremental** — perf only; the checker is already ~6s for
     the whole elpa corpus.
7. **Optional style-lint layer** — explicitly out of the type/flow scope
   (ADR-0013); Elsa/checkdoc/package-lint cover it.

## Gotchas / notes

- `make check` loads typespec **source**; stale `../emacs-typespec/*.elc` can
  shadow it — `(cd ../emacs-typespec && make clean)`.
- The walker binds `symbols-with-pos-enabled` so position-carrying symbols
  compare as bare symbols; positions are read for findings.
- The work budget (`elistan-walk--budget`, 600k) and type-size cap
  (`elistan-type--max-nodes`, 200) bound worst-case time; a pathological defun
  aborts with partial findings rather than hanging.
- Background `emacs --batch` runs in this environment were flaky (use a
  `perl -e 'alarm N; exec @ARGV' emacs ...` hard timeout for long sweeps).
