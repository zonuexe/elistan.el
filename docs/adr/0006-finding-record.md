# The finding record: structured (category + location + severity + data); rendering is separate

A finding is the analysis core's only output and the stable interchange to every
consumer — the batch driver (`file:line:col: message`), the editor driver
(Flymake `(beg end type text)`), and tests. It is a **structured record, not a
pre-baked message**: the core emits data; a separate formatter renders human
text. This keeps wording and i18n a presentation concern, and lets tests assert
on structure rather than on strings.

## Shape

A `cl-defstruct elistan-finding` with:

- **category** — a stable symbol naming the rule: `call-type-mismatch`,
  `dead-branch`, `return-type-mismatch`. The key for per-rule suppression, CLI
  codes, tests, and future doc links.
- **location** — a source position: a character offset from `symbols-with-pos`
  ([ADR-0005](0005-macro-handling.md)). A *point*, not a span; the editor driver
  derives a region (e.g. the sexp at that point), the batch driver derives
  line:col. What the point targets is category-specific:
  - `call-type-mismatch` → the offending **argument** form,
  - `dead-branch` → the **test/condition** form,
  - `return-type-mismatch` → the returning expression when identifiable, else the
    defun's name.
- **severity** — `:error` / `:warning` / `:note`. v1 uses **`:warning`** for all
  three categories (a type checker advises; it does not block). `:error` /
  `:note` are reserved.
- **data** — a category-specific **plist** of the structured facts the formatter
  needs:
  - `call-type-mismatch`: `(:function SYM :arg-index N :expected TYPE :actual TYPE)`
  - `dead-branch`: `(:test FORM :verdict always-true|always-false :dead-branch then|else)`
  - `return-type-mismatch`: `(:declared TYPE :actual TYPE)`

## Consequences

- The core never constructs strings; a formatter (shared, or per-driver) maps
  `(category . data)` → text. Adding a locale or rewording touches only the
  formatter.
- A finding on a macro-introduced node (no position) falls back to the nearest
  enclosing user position (ADR-0005); v1's categories target user-written forms,
  so this is rare.
- `data` is an open plist per category, so adding a field is backward
  compatible; adding/removing a struct slot or a category is the breaking change
  to coordinate with drivers and tests.
