# elistan — current work / handoff

Handoff for the next session. elistan is a **flow-sensitive type checker for
Emacs Lisp** built on the sibling `typespec` library (`../emacs-typespec`).
Read `AGENTS.md` first (architecture + module map), then `CONTEXT.md` (glossary)
and `docs/adr/0001`–`0014` (design decisions). v1 scope lives in
`.scratch/checker-frontend/PRD.md`.

## Status

The v1 checker front-end is **implemented, hardened on real codebases, and
extended well past v1**. On top of the original front-end this now includes:
project-wide (cross-file) checking; in-file type sources (Elsa annotations +
DBs, `cl-defstruct`/`defclass`, the file's own `(typespec …)`/`declare` forms);
**Full EIEIO** (`(:class)` static subtyping, inherited accessors, slot-typed
`oref`/`slot-value`/`oset`); lambda-body descent; `and`/`or` constant-guard
detection; deterministic (order-independent) macroexpansion; and broadened
type-predicate-guard coverage. Four finding categories: `call-type-mismatch`,
`dead-branch`, `return-type-mismatch`, `slot-type-mismatch`.

The companion `../emacs-typespec` had a coordinated foundation pass this cycle
(see "typespec coordination" below) — it must be present and current.

- Branch: **`master`** (local repo, no remote). Working tree clean; everything
  committed. (There is no `main`; `master` is the default.) `../emacs-typespec`
  is likewise clean/committed.
- **75 ert tests**, green on source *and* byte-compiled (`make check`).
- 12 source modules + 12 `*-test.el`.
- **Quality:** full elpa sweep = **743 files → 23 findings, 0 crashes**, verified
  **order-stable** and every finding a confirmed true positive; in-scope
  **recall 14/14 = 100%** (`.scratch/recall/`). See "Validation".
- **This cycle (three changes):**
  1. **Precise (strict) subtype relation** upstream in typespec
     (`typespec-eval-types-type-subtype-strict-p`), used to reduce `(diff SUB
     SUPER)` to `never` soundly — unlocking the **false-branch direction** of
     guard narrowing (`(arrayp x)` with `x : string` ⇒ else dead). Also fixed a
     latent typespec unsoundness it exposed (`(diff (const foo) keyword)` wrongly
     `never`). typespec: **162 tests** green.
  2. **`(setf (oref …) …)` slot-write checking** — the walker now `(require)`s
     eieio, so the idiomatic setf-based slot write expands to `eieio-oset`
     (instead of `setf`'s generic gv fallback mangling the place when eieio is
     unloaded) and is checked like `oset`. Closed a real recall gap.
  3. **Latent `&optional` nilability FP fixed** — `elistan-walk--seed-env` seeded
     an `&optional` param with its bare declared type, ignoring that a not-passed
     optional is `nil`; `(if opt …)` then looked never-nil → a false dead branch.
     Now seeded as `(or DECLARED null)` (strictly widening — can only *remove*
     findings). A guard disjoint from both the type and nil still fires (TP kept).
  All validated: elpa sweep **byte-identical at 23/0/order-stable** (the levers
  are additive / the FP was latent, so none fire on the corpus), recall +2
  (`dead/else-subtype`, `slot/setf-oref`).

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
  The fallback covers the common type-predicate guards (`stringp`, `integerp`,
  `arrayp`, `markerp`, `framep`, … → `(:guard! TYPE)`) for narrowing.
- `elistan-elsa.el` — reads Elsa `;; (NAME :: TYPE)` annotations *and* Elsa's
  `elsa-typed-*.el` builtin DBs (`elistan-elsa-register-typed-dbs`, opt-in,
  ~327 types). Translates Elsa notation → typespec. `elistan-elsa--corrections`
  overrides known-unsound DB return types (e.g. `help-function-arglist`) that
  would otherwise cause false-positive dead branches.
- `elistan-struct.el` — reads `cl-defstruct`/`defclass` as a type source
  (predicate guards, constructor/copier/accessor/`:reader` types). Instances are
  typed `(:class NAME)` and the class hierarchy (`:include` / defclass parents)
  is supplied to typespec's static subtyping via
  `elistan-struct-parse-hierarchy`; inherited `:include` slot accessors are
  registered (same-buffer, plus cross-file in project mode via
  `elistan-project-struct-infos`); `elistan-struct-parse-class-slots` builds the
  class→slot-type registry for `oref`/`slot-value`/`oset`. Slot `:type` becomes
  the reader return type
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
  (params + captured vars `unknown`); types `oref`/`slot-value` reads and checks
  `oset` *and* `(setf (oref/slot-value …) …)` writes (the latter via the eieio
  `(require)` so setf expands to `eieio-oset`) (`elistan-walk-class-slots`);
  flags provably-constant guards in
  `and`/`or` operands (rest unreachable). `elistan-walk--macroexpand`
  **inhibits compiler-macro inlining** so expansion is deterministic and
  source-faithful (not load-order-dependent). **Per-defun work budget** +
  symbols-with-pos. Four findings: `call-type-mismatch`, `dead-branch`,
  `return-type-mismatch`, `slot-type-mismatch`.
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
loaded: **743 files → 23 findings, 0 crashes, ~6s**, verified **order-stable**
(identical forward and reversed) and every finding individually confirmed a true
positive. Evolution from the v1 baseline of 19: lambda-body descent (+1, and its
`setq` soundness fix −1 pre-existing FP); the typespec `(const nil)` fix (+1 — a
redundant `(eq type 'year)` in a pcase `year` arm in datetime.el); `and`/`or`
constant-guard detection (+4 genuine — redundant `(or PARAM fallback)` where
PARAM is provably non-nil); and the Elsa-DB return-type correction (−1 — removed
`marginalia.el:619`, a latent false positive from Elsa typing
`help-function-arglist` as never-string, see below).

**Recall** (the other axis — `.scratch/recall/`): on a labelled in-scope bug
corpus, **14/14 caught (100%)** at 0 false positives / 0 out-of-scope leaks
(this cycle added `dead/else-subtype` — the false-branch case — and
`slot/setf-oref` — the idiomatic EIEIO slot write). The
measurement paid for itself by surfacing **three** real bugs (all fixed):
1. **Literal-argument position drop** — a *detected* call mismatch on a literal
   arg (`(f 5)`) was discarded for lack of a source position; now falls back to
   the call's function position.
2. **Order-dependent inference** (`.scratch/recall/MACROEXPAND-LEAK.md`) — the
   walker's `macroexpand-all` applied **compiler-macros** (inlining e.g.
   `char-before`), whose availability grows as files load libraries, making
   inference order-dependent and surfacing findings about inlined library
   internals. `elistan-walk--macroexpand` now inhibits compiler-macro expansion
   → deterministic, source-faithful, order-stable. (Unblocked `and`/`or`.)
3. **Latent baseline FP** — Elsa's DB typed `help-function-arglist` as
   never-string, so `(stringp (help-function-arglist f))` at `marginalia.el:619`
   was wrongly "dead"; the "20 findings, 0 FP" baseline was really 19 TP + 1 FP.
   Fixed by `elistan-elsa--corrections` (overrides unsound DB return types).

**Resolved (was a near-miss):** a `diff(SUB, SUPER) = never` reduction had been
prototyped earlier to catch the false-branch of guards (`(arrayp x)` on a
string) but was reverted as unsound, because the only available subtype check
(`type-subtype-p`) is category-coarse (reports `symbol ⊑ keyword`, distinct
`const ⊑ const`) — safe for `meet`, under-approximating for `diff`. **This cycle
implemented the sound version** (`typespec-eval-types-type-subtype-strict-p`, see
"typespec coordination" #7) and wired it into `diff`, so the false-branch
direction now works without the over-report. Re-validated: elpa sweep still
23/0/order-stable; recall includes `dead/else-subtype`.

**Latent FPs fixed this cycle** (neither fired on the corpus — the sweep stayed
byte-identical at 23 — but both were provable false-positive *classes*, caught
by reasoning and a targeted probe rather than the corpus):
1. `(diff (const foo) keyword)` wrongly reduced to `never` (coarse subtype on
   the value's category). Fixed by the strict relation (coordination #7).
2. An `&optional` param seeded with its bare declared type looked never-nil, so
   `(if opt …)` was a false dead branch. Fixed by seeding `(or DECLARED null)`
   in `elistan-walk--seed-env` (an unpassed optional is nil).
The lesson (same as the `marginalia.el:619` baseline FP): a zero-FP *corpus* is
necessary but not sufficient — latent FP classes hide behind code patterns the
corpus happens not to exercise. Probe new narrowing/seeding logic directly.

Reproduce the full sweep (load Elsa DBs, then check every elpa file):

```elisp
;; emacs -Q --batch -L . -L ../emacs-typespec -l elistan-batch --eval '(...)'
(elistan-elsa-register-typed-dbs
 (file-expand-wildcards "/Users/megurine/repo/emacs/Elsa/elsa-typed-*.el"))
(dolist (d (file-expand-wildcards "~/.emacs.d/elpa/*/"))
  (dolist (f (directory-files d t "\\.el\\'"))
    (unless (string-match-p "-autoloads\\|-pkg\\|-tests?\\.el" f)
      (condition-case e (elistan-batch-check-file f) (error ...)))))
```

Test corpora: `/Users/megurine/repo/emacs/Elsa` (annotations + builtin DBs) and
`~/.emacs.d/elpa` (~200 packages; file count drifts as packages update).

*Original v1 hardening pass (historical context)* fixed: 2 crash classes
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
   are registered in `typespec-builtins` with a `never` return. elistan's
   fallback was trimmed to just the `cl-return*` macros (`9c2317a`).
5. ~~**Promote internals to public API**~~ — *done upstream* (`ba3e471`):
   `typespec-eval-call-split-argspecs` and `typespec-eval-call-type-compatible-p`
   are now public wrappers. **Investigated adopting the splitter in
   `elistan-source-arglist` and decided against it:** the public splitter is
   *not* behavior-preserving — `typespec-eval-op-argspecs` *evaluates* each arg
   type and can return `:invalid` (a non-list that the splitter then iterates →
   crash), whereas elistan's splitter returns raw spec types and tolerates odd
   forms. Adopting it would change the FP-critical argument-checking path for no
   functional gain (the walker uses only `:required`/`:optional`/`:rest`, never
   `:keys`). Not worth the risk; leave `elistan-source-arglist` as is.
6. ~~**Class types — static subtyping**~~ — *done end-to-end* (typespec
   `6e393ba` + elistan EIEIO work): typespec decides `(:class C)` ⊑ `(:class P)`
   from `typespec-eval-types-class-parents`, and elistan emits `(:class)` and
   supplies the hierarchy.
7. ~~**Precise (strict) subtype relation**~~ — *done this cycle, upstream.* Added
   `typespec-eval-types-type-subtype-strict-p` (in `typespec-eval-numeric.el`,
   the layer that has both the type hierarchy and numeric range containment): a
   **sound** counterpart to the category-coarse `type-subtype-p` — it never
   over-reports (no `symbol ⊑ keyword`, no overlapping-range collapse), widening
   only the *sub* side to its category and consulting the precise elisp
   hierarchy/range containment. `typespec-eval-op-diff` now reduces `(diff SUB
   SUPER)` to `never` when strict-subtype holds, which **unlocks the
   false-branch direction of guard narrowing** in elistan (e.g. `(arrayp x)`
   with `x : string` ⇒ the else branch is dead). The const-minus-type branch of
   `diff` was routed through the strict relation too, fixing a **latent
   unsoundness**: `(diff (const foo) keyword)` used to reduce to `never` (it used
   the coarse subtype on the value's category — `foo` is a symbol, "same
   category" as `keyword`), now correctly stays `(const foo)`. Containment logic
   was promoted to `typespec-eval-numeric-range-subset-p` (the call-checker's
   `--numeric-subtype-p` delegates to it). typespec `make check` = 162/162.

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
4. **Full EIEIO** — essentially **done**:
   - ~~(a) emit `(:class NAME)` + supply hierarchy~~ — done (typespec `6e393ba`
     static subtyping; elistan emits `(:class)`, drivers bind
     `typespec-eval-types-class-parents`). Subclass accepted where superclass
     wanted; `(child-p x)` narrows a superclass var to the subclass.
   - ~~(b) inherited `:include` accessors~~ — done (same-buffer + cross-file in
     project mode via `elistan-project-struct-infos`).
   - ~~(c) slot-typed `oref`/`slot-value` reads~~ — done
     (`elistan-walk--oref` + `elistan-walk-class-slots`, inheritance-aware).
   - ~~(d) `oset`/`eieio-oset` value checking~~ — done
     (`slot-type-mismatch` finding; gated on provable disjointness, EIEIO
     enforces defclass slot `:type`).
   - ~~(e) `(setf (oref …) …)` / `(setf (slot-value …) …)` writes~~ — *done this
     cycle.* `elistan-walk.el` now `(require)`s eieio, so these expand to
     `eieio-oset` and are checked like `oset`. (Without eieio loaded, `setf` has
     no place expander for `oref` and its generic gv fallback mangles the form —
     the slot name is evaluated as a variable — so the write was invisible.
     Loading eieio unconditionally + upfront is deterministic; compiler-macros
     stay inhibited in `elistan-walk--macroexpand`.) Sweep byte-identical at
     23/0; recall +1 (`slot/setf-oref`).
   Design note: under zero-FP + EIEIO's open world, class subtyping adds
   *acceptance/narrowing precision*, not rejection of unrelated classes (that
   would be unsound).
5. ~~**Elsa DB soundness + guard coverage**~~ — *done this cycle.* Corrected
   unsound Elsa return types (`elistan-elsa--corrections`) and broadened
   type-predicate-guard coverage (`elistan-source--fallback`: `arrayp`,
   `markerp`, …). Spot-audit of ~45 common functions shows Elsa's DB is
   otherwise sound; a full 327-entry audit is low-yield.

### Remaining work (for the next session)

**The high-value, zero-FP-safe backlog is exhausted.** The precise subtype
relation (the last "only lever that doesn't trade against zero-FP") landed this
cycle, along with the `(setf (oref …) …)` slot write and the `&optional`
nilability fix. What remains is either *unsafe* (would risk false positives,
against the project's defining constraint), *no-value*, or *perf-only* — each
annotated below with why. Don't pick one up expecting an easy win; re-read the
note first.

**Lower value / thorny** (see PRD "Deferred / future"):
- **Flycheck backend** — postponed by request; needs an optional-dependency
  build decision (flycheck isn't on the `make` load-path — add it, or exclude
  the file from `make compile`). Mirrors `elistan-flymake.el` otherwise.
- **non-function top-level forms** — *unsafe naively*: most top-level definition
  macros (`compat-defun`, `cl-defmethod`, `use-package`, …) aren't loaded during
  analysis, so `macroexpand-all` leaves them and walking them as expressions
  yields FPs + crashes (verified). A sound version must gate on "head is a loaded
  function", which excludes the interesting macro targets — safe slice is low
  value.
- **`&key`/`cl-defun` params** — elistan only argument-checks authoritative
  in-file contracts, which essentially never declare typed `&key` today (typespec
  *does* support `&key` for result typing already). Low marginal value.
  (Note: `cl-defun` extended arglists — `(x default)`, `&key`, `&aux` — were
  audited this cycle and degrade *safely* to untracked/`unknown`; no FP/crash,
  just imprecision.)
- **precise `catch`/`condition-case`** — basic `throw` divergence already works
  via the `never` fallback; precise tag-matching is low value.
- **changed-only incremental** — perf only; the checker is ~6s for all of elpa.
- **adopt typespec's public splitter** — *investigated and rejected this cycle*;
  not behavior-preserving and no functional gain (see coordination #5 for the
  full rationale).
- **strict relation: structured supers** — *low value*; the strict subtype
  relation answers `nil` for container/function/tuple *supers* (covariant
  elements), which is sound but imprecise. Guards never produce such supers, so
  sharpening `diff` here would not fire in practice (see coordination #7).

**Out of scope:** optional style-lint layer (ADR-0013; Elsa/checkdoc/
package-lint cover it).

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
