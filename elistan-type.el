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
  "Return non-nil if a VALUE-typed thing is acceptable where EXPECTED is wanted.

This is gradual consistency: the dynamic (`unknown') is consistent with every
type in both directions.  Otherwise it defers to typespec's compatibility
check.

TODO: promote to typespec as the public gradual-consistency relation, replacing
the direct call to the internal `typespec-eval-call--type-compatible-p'."
  (cond
   ((or (elistan-type-dynamic-p value) (elistan-type-dynamic-p expected)) t)
   (t (typespec-eval-call--type-compatible-p value expected))))

(defun elistan-type-meet (a b)
  "Intersect types A and B (the true-branch refinement operation).
The dynamic narrows to the other operand."
  (cond
   ((elistan-type-dynamic-p a) b)
   ((elistan-type-dynamic-p b) a)
   (t (typespec-eval-op-and (list a b)))))

(defun elistan-type-diff (a b)
  "Subtract type B from type A (the false-branch refinement operation).
Subtracting from the dynamic leaves it dynamic."
  (if (elistan-type-dynamic-p a)
      a
    (typespec-eval-op-diff a b)))

(defun elistan-type-union (&rest types)
  "Return the union of TYPES."
  (typespec-eval-simplify-or types))

(defun elistan-type-never-p (type)
  "Return non-nil if TYPE is the bottom type `never' (after normalisation)."
  (eq (typespec-eval type) 'never))

(defun elistan-type-always-nil-p (type)
  "Return non-nil if a TYPE-typed value is provably always nil."
  (let ((ty (typespec-eval type)))
    (or (eq ty 'null)
        (equal ty '(const nil)))))

(defun elistan-type-never-nil-p (type)
  "Return non-nil if a TYPE-typed value is provably never nil (always truthy)."
  (let ((ty (typespec-eval type)))
    (and (not (elistan-type-dynamic-p ty))
         (not (elistan-type-top-p ty))
         (not (memq ty '(null never)))
         ;; nil is not a member: `null' is not acceptable where TY is expected.
         (not (elistan-type-consistent-p 'null ty)))))

(provide 'elistan-type)
;;; elistan-type.el ends here
