;;; elistan-type.el --- Gradual type operations for elistan  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  USAMI Kenta

;; Author: USAMI Kenta <tadsan@zonu.me>
;; Keywords: lisp, extensions, tools
;; License: GPL-3.0-or-later

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A thin facade over typespec's type algebra, adding elistan's gradual-dynamic
;; treatment of `unknown'.
;;
;; Boundary note (see CONTEXT.md, docs/adr/0003): the *meaning* of types is
;; typespec's; elistan only orchestrates.  Some operations here are destined for
;; typespec proper — in particular the gradual-dynamic consistency relation
;; (typespec currently treats `unknown' as a top type only on the expected side;
;; elistan needs it consistent in *both* directions).  Until that lands in
;; typespec, the gradual layer lives here, funnelled through a few functions so
;; it can be promoted/merged later.

;;; Code:

(require 'typespec-eval)

(defconst elistan-type-dynamic 'unknown
  "The gradual dynamic type — consistent with every type in both directions.")

(defun elistan-type-dynamic-p (type)
  "Return non-nil if TYPE is the gradual dynamic, or a union containing it."
  (or (eq type elistan-type-dynamic)
      (and (consp type) (eq (car type) 'or)
           (seq-some #'elistan-type-dynamic-p (cdr type)))))

(defun elistan-type-top-p (type)
  "Return non-nil if TYPE is the top type (`mixed' / `t')."
  (memq type '(mixed t)))

(defun elistan-type-consistent-p (value expected)
  "Return non-nil unless VALUE and EXPECTED are *provably* incompatible.

This is the gradual acceptance relation behind the robustness posture
(docs/adr/0004): a finding is emitted only when the two types are disjoint
(their intersection is `never').  Anything that merely cannot be proven
compatible — a wider value where a narrower type is wanted, a union that
partly overlaps — is accepted, so the checker stays free of false positives.
The dynamic (`unknown') is consistent with everything, in both directions.

TODO: promote to typespec as the public gradual-consistency relation."
  (cond
   ((or (elistan-type-dynamic-p value) (elistan-type-dynamic-p expected)) t)
   ;; `never' is the bottom type: assignable anywhere, and a `never'-typed value
   ;; means the code path is unreachable, so there is nothing to flag.
   ((elistan-type-never-p value) t)
   (t (not (elistan-type-never-p (elistan-type-meet value expected))))))

;; The typespec foundation is still maturing and can error on some inputs (e.g.
;; intersecting two half-bounded integer ranges).  A checker must never crash on
;; valid source, so every call into typespec here is guarded with a conservative
;; fallback.  Over-approximating (keeping a wider type) is always safe: it can
;; only lose precision, never create a false positive.

(defun elistan-type--eval (type)
  "Normalise TYPE via typespec, or return it unchanged if typespec errors."
  (condition-case nil (typespec-eval type) (error type)))

(defconst elistan-type--max-nodes 200
  "Types larger than this collapse to `unknown'.
Bounds the cost of type operations so a huge accumulated type (e.g. a union
built up across a giant generated function) cannot blow up; over-approximating
to the dynamic is always safe.")

(defun elistan-type--small-p (type)
  "Return non-nil if TYPE has at most `elistan-type--max-nodes' cons cells.
Iterative and improper-list-safe."
  (let ((stack (list type)) (n 0))
    (catch 'big
      (while stack
        (let ((x (pop stack)))
          (while (consp x)
            (when (> (setq n (1+ n)) elistan-type--max-nodes) (throw 'big nil))
            (push (car x) stack)
            (setq x (cdr x)))))
      t)))

(defun elistan-type--cap (type)
  "Collapse TYPE to `unknown' when it is too large to operate on cheaply."
  (if (elistan-type--small-p type) type 'unknown))

(defun elistan-type-meet (a b)
  "Intersect types A and B (the true-branch refinement operation).
The dynamic narrows to the other operand."
  (cond
   ((elistan-type-dynamic-p a) b)
   ((elistan-type-dynamic-p b) a)
   (t (elistan-type--cap
       (condition-case nil (typespec-eval-op-and (list a b)) (error a))))))

(defun elistan-type-diff (a b)
  "Subtract type B from type A (the false-branch refinement operation).
Subtracting from the dynamic leaves it dynamic."
  (if (elistan-type-dynamic-p a)
      a
    (elistan-type--cap
     (condition-case nil (typespec-eval-op-diff a b) (error a)))))

(defun elistan-type-union (&rest types)
  "Return the union of TYPES."
  (elistan-type--cap
   (condition-case nil (typespec-eval-simplify-or types) (error 'unknown))))

(defun elistan-type-never-p (type)
  "Return non-nil if TYPE is the bottom type `never' (after normalisation)."
  (eq (elistan-type--eval type) 'never))

(defun elistan-type-always-nil-p (type)
  "Return non-nil if a TYPE-typed value is provably always nil."
  (let ((ty (elistan-type--eval type)))
    (or (eq ty 'null)
        (equal ty '(const nil)))))

(defun elistan-type-never-nil-p (type)
  "Return non-nil if a TYPE-typed value is provably never nil (always truthy)."
  (let ((ty (elistan-type--eval type)))
    (and (not (elistan-type-dynamic-p ty))
         (not (elistan-type-top-p ty))
         (not (memq ty '(null never)))
         ;; A provably-nil type is obviously not never-nil (guards against a
         ;; typespec quirk where `(const nil)' mis-intersects with `null').
         (not (elistan-type-always-nil-p ty))
         ;; nil is not a member: `null' is not acceptable where TY is expected.
         (not (elistan-type-consistent-p 'null ty)))))

(provide 'elistan-type)
;;; elistan-type.el ends here
