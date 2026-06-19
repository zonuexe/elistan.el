;;; elistan-recognise.el --- Condition recognition and refinements  -*- lexical-binding: t; -*-

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

;; Recognises a test form and produces a *refinement* (docs/adr/0009): an alist
;; mapping each constrained variable to a `(TRUE-TYPE . FALSE-TYPE)' pair — the
;; types it has in the true and false branches.  `elistan-refine-true' and
;; `elistan-refine-false' apply a refinement to an environment.
;;
;; Recognisers cover guard predicates, `null'/`not', `eq'/`eql'/`equal' to a
;; constant, `memq'/`member', integer comparisons, a bare variable used as a
;; test, and `and'/`or'/`not' composition.  The disjunctive side of `and'/`or'
;; is widened (left unchanged), per the robustness posture.
;;
;; v1 narrows only *direct variable references*; access-path / occurrence typing
;; (e.g. `(stringp (car x))') and multi-variable relations are out of scope.

;;; Code:

(require 'cl-lib)
(require 'elistan)
(require 'elistan-type)
(require 'elistan-source)
(require 'typespec-eval)

;;; Applying refinements

(defun elistan-refine-true (env refinement)
  "Return ENV with each variable in REFINEMENT bound to its true-branch type."
  (let ((e env))
    (dolist (cell refinement e)
      (setq e (elistan-env-set e (car cell) (cadr cell))))))

(defun elistan-refine-false (env refinement)
  "Return ENV with each variable in REFINEMENT bound to its false-branch type."
  (let ((e env))
    (dolist (cell refinement e)
      (setq e (elistan-env-set e (car cell) (cddr cell))))))

;;; Helpers

(defun elistan-recognise--var-p (form)
  "Return non-nil if FORM is a plain variable reference we may narrow."
  (and (symbolp form) (not (memq form '(nil t))) (not (keywordp form))))

(defun elistan-recognise--const (form)
  "Return the constant type `(const V)' for a literal FORM, or nil."
  (cond
   ((and (consp form) (eq (car form) 'quote)) (list 'const (cadr form)))
   ((or (numberp form) (stringp form) (keywordp form) (memq form '(t nil)))
    (list 'const form))
   (t nil)))

(defun elistan-recognise--cell (var true false)
  "Build a one-variable refinement binding VAR to TRUE / FALSE branch types."
  (list (cons var (cons true false))))

;;; Individual recognisers

(defun elistan-recognise--nilness (var env)
  "Refine VAR by truthiness: true branch non-nil, false branch nil."
  (let ((cur (elistan-env-get env var)))
    (elistan-recognise--cell var
                             (elistan-type-diff cur 'null)
                             (elistan-type-meet cur 'null))))

(defun elistan-recognise--predicate (pred arg env)
  "Refine ARG when PRED is a guard predicate resolved from the type source."
  (when (elistan-recognise--var-p arg)
    (let ((funspec (elistan-source-function-spec pred)))
      (when funspec
        (let* ((cur (elistan-env-get env arg))
               (narrowing (typespec-eval-call-narrowing funspec (list cur))))
          (when narrowing
            (if (plist-member narrowing :assert)
                (elistan-recognise--cell arg (plist-get narrowing :assert) cur)
              (elistan-recognise--cell arg
                                       (plist-get narrowing :true)
                                       (plist-get narrowing :false)))))))))

(defun elistan-recognise--narrow-const (var const-type env)
  "Refine VAR against equality to CONST-TYPE."
  (let ((cur (elistan-env-get env var)))
    (elistan-recognise--cell var
                             (elistan-type-meet cur const-type)
                             (elistan-type-diff cur const-type))))

(defun elistan-recognise--eq (a b env)
  "Refine an `eq'/`eql'/`equal' between operands A and B (one var, one const)."
  (let* ((ca (elistan-recognise--const a))
         (cb (elistan-recognise--const b)))
    (cond
     ((and cb (not ca) (elistan-recognise--var-p a))
      (elistan-recognise--narrow-const a cb env))
     ((and ca (not cb) (elistan-recognise--var-p b))
      (elistan-recognise--narrow-const b ca env))
     (t nil))))

(defun elistan-recognise--memq (x lst env)
  "Refine `(memq X (quote ITEMS))' when X is a variable and ITEMS a literal."
  (when (and (elistan-recognise--var-p x)
             (consp lst) (eq (car lst) 'quote) (consp (cadr lst)))
    (let* ((items (cadr lst))
           (set (apply #'elistan-type-union
                       (mapcar (lambda (it) (list 'const it)) items)))
           (cur (elistan-env-get env x)))
      (elistan-recognise--cell x
                               (elistan-type-meet cur set)
                               (elistan-type-diff cur set)))))

(defun elistan-recognise--flip-op (op)
  "Flip comparison OP for a `(OP CONST VAR)' shape."
  (pcase op ('< '>) ('> '<) ('<= '>=) ('>= '<=) (_ op)))

(defun elistan-recognise--compare (op a b env)
  "Refine an integer comparison (OP A B) with one variable and one int literal."
  (let (var n flip)
    (cond
     ((and (elistan-recognise--var-p a) (integerp b)) (setq var a n b))
     ((and (elistan-recognise--var-p b) (integerp a)) (setq var b n a flip t)))
    (when var
      (let* ((o (if flip (elistan-recognise--flip-op op) op))
             (cur (elistan-env-get env var)))
        ;; Sound only when the variable is (or could be) an integer.
        (when (or (elistan-type-dynamic-p cur)
                  (typespec-eval-types-type-subtype-p cur 'integer))
          (cl-flet ((m (lo hi) (elistan-type-meet cur (list 'integer lo hi)))
                    (d (lo hi) (elistan-type-diff cur (list 'integer lo hi))))
            (pcase o
              ('>  (elistan-recognise--cell var (m (1+ n) '*) (m '* n)))
              ('>= (elistan-recognise--cell var (m n '*) (m '* (1- n))))
              ('<  (elistan-recognise--cell var (m '* (1- n)) (m n '*)))
              ('<= (elistan-recognise--cell var (m '* n) (m (1+ n) '*)))
              ('=  (elistan-recognise--cell var (m n n) (d n n)))
              ('/= (elistan-recognise--cell var (d n n) (m n n)))
              (_ nil))))))))

;;; Composition

(defun elistan-recognise--not (refinement)
  "Swap the true and false types of REFINEMENT."
  (mapcar (lambda (cell) (cons (car cell) (cons (cddr cell) (cadr cell))))
          refinement))

(defun elistan-recognise--and (conds env)
  "Refine `(and . CONDS)': true is precise (progressive), false is widened."
  (let ((e env) (vars nil))
    (dolist (c conds)
      (let ((r (elistan-recognise c e)))
        (when r
          (setq e (elistan-refine-true e r))
          (dolist (cell r) (cl-pushnew (car cell) vars)))))
    (when vars
      (mapcar (lambda (v) (cons v (cons (elistan-env-get e v)
                                        (elistan-env-get env v))))
              (nreverse vars)))))

(defun elistan-recognise--or (conds env)
  "Refine `(or . CONDS)': false is precise (progressive), true is widened."
  (let ((e env) (vars nil))
    (dolist (c conds)
      (let ((r (elistan-recognise c e)))
        (when r
          (setq e (elistan-refine-false e r))
          (dolist (cell r) (cl-pushnew (car cell) vars)))))
    (when vars
      (mapcar (lambda (v) (cons v (cons (elistan-env-get env v)
                                        (elistan-env-get e v))))
              (nreverse vars)))))

;;; Dispatch

(defun elistan-recognise (form env)
  "Recognise test FORM under ENV and return its refinement, or nil."
  (pcase form
    (`(not ,arg)
     (let ((r (elistan-recognise arg env)))
       (and r (elistan-recognise--not r))))
    (`(and . ,conds) (elistan-recognise--and conds env))
    (`(or . ,conds) (elistan-recognise--or conds env))
    (`(,(or 'eq 'eql 'equal) ,a ,b) (elistan-recognise--eq a b env))
    (`(,(or 'memq 'memql 'member) ,x ,lst) (elistan-recognise--memq x lst env))
    (`(,(and op (or '< '> '<= '>= '= '/=)) ,a ,b)
     (elistan-recognise--compare op a b env))
    (`(,(and pred (pred symbolp)) ,arg) (elistan-recognise--predicate pred arg env))
    ((pred elistan-recognise--var-p) (elistan-recognise--nilness form env))
    (_ nil)))

(provide 'elistan-recognise)
;;; elistan-recognise.el ends here
