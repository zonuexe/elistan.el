# elistan

elistan is a flow-sensitive type checker for Emacs Lisp. It is the analyzer and
holds all the reins: it walks the code, threads each variable's type across
control flow, resolves where a function's type comes from, and decides what to
report. [typespec](../emacs-typespec) is its low-level type-operations toolkit
(and one of several type sources) — not the analyzer itself. This glossary is
elistan's own vocabulary.

## Language

**Analysis core**:
The pure engine that takes already-read Emacs Lisp forms and produces findings.
It performs no I/O and never parses source text — it sees forms, not characters.
_Avoid_: engine, checker (ambiguous between the core and the whole tool)

**Driver**:
A thin layer that obtains forms for the analysis core and presents its findings.
Two exist: the *batch driver* (reads files for CLI/CI) and the *editor driver*
(feeds the form under edit and renders in-buffer diagnostics).
_Avoid_: frontend, backend

**Finding**:
A single issue the analysis core reports — the unit of output handed to drivers.
A structured record (category, location, severity, category-specific data), not
a pre-baked message; see `docs/adr/0006-finding-record.md`.
_Avoid_: error, warning, lint; diagnostic (reserve that for the editor driver's
rendered form)

**Formatter**:
The presentation step that renders a finding's `(category . data)` into human
text. Lives outside the core, so wording and locale are not the core's concern.
_Avoid_: printer, reporter

**Type source**:
A place elistan can learn a function's type — a declared typespec, Emacs
built-in knowledge, Elsa-style comment annotations, or inference. typespec is
*one* source among these (as RBS is one of Rigor's), not a privileged one. v1
wires only the declared-typespec source.
_Avoid_: provider, backend

**Declared typespec**:
A function's type recorded on its symbol, retrievable without consulting its
body — the one type source wired in v1.
_Avoid_: signature, annotation

**Controlled expansion**:
The core's policy of expanding macros (by default) down to special forms before
analysing them, while a small reserved *short-circuit list* (empty in v1) names
macros to interpret at the surface instead.
_Avoid_: macroexpansion (that names the raw operation, not this policy)

**Expander**:
The function a driver supplies that expands macros against the live Emacs
environment, so the analysis core can stay pure.
_Avoid_: macroexpander

**Type environment**:
The mapping from each in-scope variable to its currently known type, threaded
through a function body as the core walks control flow.
_Avoid_: context, scope, type context

**Narrowing**:
Refining a variable's type within a branch because a condition tested it (e.g. a
guard predicate succeeding), yielding distinct environments for the true and
false branches. elistan recognises the condition and drives the refinement;
typespec computes the refined type.
_Avoid_: type guard (the guard *effect* is typespec's term)

**Refinement**:
The data a recognised condition produces: a map `variable → (:true P :false N)`
of types to intersect with each variable's current type, per branch. Composed
for `and`/`or`/`not`, then applied to the environment — the narrowing step. See
`docs/adr/0009-narrowing-representation.md`.
_Avoid_: predicate, fact

**Recogniser**:
An entry in elistan's registry mapping a condition shape (a guard predicate,
`eq`-to-const, a comparison, `memq`, `null`/`not`, …) to the refinement it
implies. Adding a narrowing case means adding a recogniser.
_Avoid_: matcher, handler

**Join** (at a **confluence**):
Combining the type environments of branches that merge back together, by
unioning each variable's type. A confluence is the program point where the
merge happens.
_Avoid_: merge; union (union is the type-algebra operation, not this env step)

**Gradual dynamic** (`unknown`):
The type that is consistent with every type in *both* directions — so using it
never produces a finding. It is elistan's no-information default, spelled
`unknown`, and is a first-class concept in typespec's type system (see
`docs/adr/0003-elistan-holds-reins-typespec-toolkit.md`). Conceptually separate
from top.
_Avoid_: any; mixed, top (those name the universal supertype, not the dynamic)

**Top** (`mixed`):
The universal supertype — every value inhabits it. *Not* the dynamic: a top
value does not silently satisfy a specific required type (that needs narrowing).
_Avoid_: any, unknown, dynamic

**Divergence** (`never`):
A form that does not return to its continuation — `throw`, `signal`/`error`,
`cl-return*`, … — has value type `never` (the bottom type). A confluence joins
only the branches that *don't* diverge, which is what gives guard-clause /
early-exit narrowing (see `docs/adr/0010-walker-threading-and-divergence.md`).
_Avoid_: bottom (that names the type; this is the control concept), noreturn
