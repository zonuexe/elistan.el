# Macro handling: native special forms, expand-by-default macros, injected expander

Emacs Lisp control flow is split between **special forms** (`if`, `cond`, `and`,
`or`, `progn`, `prog1`, `let`, `let*`, `while`, `quote`, `function`, `catch`,
`condition-case`, `unwind-protect`, `save-*`, …) and **macros** (`when`,
`unless`, `pcase`, `cl-typecase`, `when-let`, `dolist`, and every user macro).
The analysis core treats them as:

1. **Special forms are interpreted natively.** They never macroexpand; they are
   the irreducible residual every macro bottoms out in, and the closed set the
   walker must implement. `and`/`or` belong here — they are special forms, not
   "short-circuited macros".
2. **Macros are expanded by default** (controlled expansion). Evidence: Emacs
   macros overwhelmingly expand into special forms + guard predicates (`stringp`,
   `consp`) + typed primitives (`car-safe`) — exactly what elistan's narrowing
   and typespec already handle. `cl-typecase` → `cond` of `stringp`/`integerp`;
   `when-let` → `let*` + `if`; a simple `pcase` cons pattern → `consp` + the
   `car-safe`/`cdr-safe` bindings. Expansion therefore *preserves* most
   narrowing for free and covers user-defined macros automatically.
3. **A native macro short-circuit list is reserved, and empty in v1.**
   Interpreting a macro at the surface instead of expanding it is only warranted
   where expansion *loses* analysable structure, hurts diagnostics, or is
   intractable (complex `pcase` backtracking, `cl-loop`, `cl-defstruct`). The
   "basic forms" worth handling directly are already special forms, so no actual
   macro needs short-circuiting in v1.
4. **Functions appearing in conditions** (`not`, `null`, `stringp`, …) are not
   forms to walk but conditions to recognise; their narrowing comes from guard
   typespecs.
5. **Unexpandable macros** (not loaded, or expansion refused) are opaque: result
   `unknown`, no descent, no finding (robustness posture, [ADR-0004](0004-robustness-posture.md)).

## Where expansion sits, and the pure core

Expansion touches the live macro environment, so it sits at the acquisition
boundary (drivers — [ADR-0001](0001-pure-analysis-core-and-drivers.md)); the
pure core receives expanded forms. To keep *which macros to expand* (the
short-circuit policy) in the core, where analysis policy belongs
([ADR-0003](0003-elistan-holds-reins-typespec-toolkit.md)), the core is
parameterised by an injected **expander** that a driver supplies — backed by the
live environment (the batch driver after `require`-ing the file's dependencies,
the editor driver best-effort). In v1 the short-circuit set is empty, so this
reduces to the driver handing the core fully `macroexpand-all`-ed forms.

## Positions

Reading with `symbols-with-pos-enabled` (Emacs 29.1+, already required)
preserves source positions on the user's own symbols through expansion, so
findings map back to buffer locations even when analysis runs on expanded forms.
Macro-introduced temporaries carry no position, but findings rarely target them.

## Mechanism

With an empty short-circuit set, full `macroexpand-all` up front (then walk the
special forms) is the simplest mechanism. An incremental `macroexpand-1` walk —
expand one level, re-dispatch, stop at short-circuited macros — becomes
worthwhile only once the short-circuit list grows.
