;;; elistan.el --- A flow-sensitive type checker for Emacs Lisp  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  USAMI Kenta

;; Author: USAMI Kenta <tadsan@zonu.me>
;; Homepage: https://github.com/zonuexe/elistan
;; Keywords: lisp, extensions, tools
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (typespec "0.0.1"))
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

;; elistan is a flow-sensitive type checker for Emacs Lisp built on top of the
;; `typespec' type-operations foundation.  typespec owns the *meaning* of the
;; type notation (the type algebra, subtyping, type-level evaluation, and the
;; guard/assert narrowing effect); elistan owns the *orchestration* of those
;; operations over real code: tracking variable types and refining them across
;; conditional branches.
;;
;; This module provides the flow-sensitivity layer:
;; - A type environment (`var -> type') with `elistan-env-make/get/set'.
;; - `elistan-env-narrow' applies a guard/assert predicate tested on a variable,
;;   returning the refined environments per branch, via the foundation's
;;   `typespec-eval-call-narrowing'.
;; - `elistan-env-join' unions each variable's type at a control-flow confluence.
;;
;; Driving these from the syntax of a function body — walking `if'/`cond'/
;; `when'/`and'/`or'/`let', resolving calls, and tracking lexical bindings — is
;; the checker front-end, to be built on top of this layer.

;;; Code:

(require 'typespec-eval)

(defconst elistan-env-default 'unknown
  "Type assumed for variables absent from a type environment.")

(defun elistan-env-make (&optional bindings)
  "Return a new type environment from BINDINGS, an alist of (VAR . TYPE)."
  (copy-alist bindings))

(defun elistan-env-get (env var)
  "Return the type bound to VAR in ENV, or `elistan-env-default'."
  (let ((cell (assq var env)))
    (if cell (cdr cell) elistan-env-default)))

(defun elistan-env-set (env var type)
  "Return a new environment like ENV with VAR bound to TYPE."
  (cons (cons var type)
        (assq-delete-all var (copy-alist env))))

(defun elistan-env-narrow (env var funspec)
  "Refine ENV for a guard FUNSPEC tested on VAR.
FUNSPEC is a function typespec whose return is `:guard'/`:guard!'/`:assert'.
Return a plist describing the refined environments per branch:
- (:true ENV-TRUE :false ENV-FALSE) for `:guard'/`:guard!'.  For `:guard' the
  false environment is ENV unchanged (the predicate may be partial).
- (:assert ENV-ASSERT) for `:assert'.
Return nil when FUNSPEC has no guard/assert effect."
  (let* ((arg0 (elistan-env-get env var))
         (narrowing (typespec-eval-call-narrowing funspec (list arg0))))
    (when narrowing
      (if (plist-member narrowing :assert)
          (list :assert
                (elistan-env-set env var (plist-get narrowing :assert)))
        (list :true
              (elistan-env-set env var (plist-get narrowing :true))
              :false
              (elistan-env-set env var (plist-get narrowing :false)))))))

(defun elistan-env-join (env-a env-b)
  "Join environments ENV-A and ENV-B at a control-flow confluence.
Each variable's type becomes the union of its type in each environment
\(variables absent on one side default to `elistan-env-default')."
  (let ((vars (delete-dups (append (mapcar #'car env-a) (mapcar #'car env-b))))
        (result nil))
    (dolist (var vars)
      (push (cons var
                  (typespec-eval-simplify-or
                   (list (elistan-env-get env-a var)
                         (elistan-env-get env-b var))))
            result))
    (nreverse result)))

(provide 'elistan)
;;; elistan.el ends here
