# Editor driver: per-top-level-form analysis unit (incremental by construction), skipping unreadable forms

The editor driver (use case A, Flymake/Flycheck) acquires forms from the live
buffer and renders findings as diagnostics.

- **Unit = a single top-level form.** Because defuns are self-contained
  ([ADR-0002](0002-declared-typespec-only-v1.md)), top-level forms analyse
  independently, so **incrementality is automatic**: only the changed top-level
  form(s) need re-analysis, with no cross-form invalidation. This is how use
  case A's "fast / resident" requirement is met with no extra machinery. v1 may
  simply analyse every top-level form in the region Flymake requests (each is
  cheap and independent); a changed-only optimisation is a later refinement.
- **Unreadable forms are skipped silently.** A form mid-edit (an incomplete
  sexp) or a syntax error makes `read` fail; the driver catches and skips it.
  Syntax/parse errors are **not** elistan findings — that is the byte-compiler's
  / checkdoc's job, and the robustness posture
  ([ADR-0004](0004-robustness-posture.md)) says stay silent on what we cannot
  analyse.
- **v1 analyses function-defining top-level forms only** (`defun`, `defsubst`,
  `cl-defun`, …). Other top-level forms (`defvar`, bare expressions, …) are out
  of scope for v1 — narrower scope, fewer false positives. Analysing arbitrary
  top-level forms as expressions is a later extension.
- **Reading uses `symbols-with-pos-enabled`** so finding positions map to buffer
  regions ([ADR-0005](0005-macro-handling.md)); findings become Flymake
  diagnostics via the formatter ([ADR-0006](0006-finding-record.md)). Macros not
  loaded in the live session expand best-effort → opaque/`unknown`, no finding
  (ADR-0005).
