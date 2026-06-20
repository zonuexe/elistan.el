;;; elistan-source.el --- Function type-source resolution for elistan  -*- lexical-binding: t; -*-

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

;; Resolves a function symbol to its declared funspec — the v1 type source
;; (docs/adr/0002).  Resolution order: a user `typespec' declaration, then
;; typespec's builtin registry, then elistan's own fallback coverage.
;;
;; The fallback table (`elistan-source--fallback') exists because typespec's
;; builtin registry is currently sparse; per the project plan this coverage
;; belongs in typespec-builtins and lives here only until migrated.

;;; Code:

(require 'typespec-eval)
(require 'typespec-builtins)

(defconst elistan-source--fallback
  '((stringp        . (function (t) (:guard! string)))
    (integerp       . (function (t) (:guard! integer)))
    (natnump        . (function (t) (:guard! (integer 0 *))))
    (numberp        . (function (t) (:guard! number)))
    (floatp         . (function (t) (:guard! float)))
    (symbolp        . (function (t) (:guard! symbol)))
    (keywordp       . (function (t) (:guard! keyword)))
    (booleanp       . (function (t) (:guard! boolean)))
    (consp          . (function (t) (:guard! cons)))
    (listp          . (function (t) (:guard! list)))
    (vectorp        . (function (t) (:guard! vector)))
    (functionp      . (function (t) (:guard! function)))
    (hash-table-p   . (function (t) (:guard! hash-table)))
    (bufferp        . (function (t) (:guard! buffer)))
    (null           . (function (t) (:guard! null)))
    (not            . (function (t) (:guard! null)))
    ;; Non-returning functions: a `never' return drives divergence (ADR-0010).
    (error                . (function (&rest mixed) never))
    (signal               . (function (&rest mixed) never))
    (user-error           . (function (&rest mixed) never))
    (throw                . (function (&rest mixed) never))
    (cl-return            . (function (&rest mixed) never))
    (cl-return-from       . (function (&rest mixed) never))
    (keyboard-quit        . (function () never))
    (abort-recursive-edit . (function () never))
    (top-level            . (function () never))
    ;; A little ordinary coverage so v1 is useful out of the box.
    (length            . (function (sequence) integer))
    (concat            . (function (&rest sequence) string))
    (symbol-name       . (function (symbol) string))
    (number-to-string  . (function (number) string))
    (string-to-number  . (function (string &optional integer) number))
    (1+                . (function (number) number))
    (1-                . (function (number) number))
    (+                 . (function (&rest number) number))
    (-                 . (function (&rest number) number))
    (*                 . (function (&rest number) number))
    (identity          . (function (mixed) mixed)))
  "elistan's own fallback function-type coverage.
Consulted only when typespec has neither a declaration nor a builtin entry.
TODO: migrate this coverage into typespec-builtins.")

(defvar elistan-source-local nil
  "Dynamic alist of NAME -> funspec parsed from the file under analysis.
Highest-priority type source: a driver binds this to in-file declarations or
annotations (e.g. Elsa `;; (NAME :: TYPE)' comments) before checking, so a
function's own file can supply its type.")

(defun elistan-source-function-spec (sym)
  "Return the funspec for function SYM, or nil if unknown.
Order: an in-file annotation (`elistan-source-local'), then a user `typespec'
declaration, then typespec's builtin registry, then elistan's fallback."
  (and (symbolp sym)
       (or (cdr (assq sym elistan-source-local))
           (plist-get (function-get sym 'typespec) :spec)
           (typespec-builtins-lookup sym)
           (cdr (assq sym elistan-source--fallback)))))

(defun elistan-source-return (funspec)
  "Return the declared return type of FUNSPEC, or nil if FUNSPEC is not a spec."
  (pcase funspec
    (`(:forall ,_ ,body) (elistan-source-return body))
    (`(function ,_ ,ret) ret)
    (_ nil)))

(defun elistan-source-arglist (funspec)
  "Split FUNSPEC's argument list into a plist (:required :optional :rest).
:rest holds the element type of a &rest parameter, or nil.  Returns nil when
FUNSPEC is not a function spec.

TODO: typespec has an internal `typespec-eval-call--split-argspecs'; promote it
to public API and reuse it here."
  (pcase funspec
    (`(:forall ,_ ,body) (elistan-source-arglist body))
    (`(function ,argspecs ,_)
     (let ((state 'required) required optional rest)
       (dolist (spec argspecs)
         (pcase spec
           ('&optional (setq state 'optional))
           ('&rest (setq state 'rest))
           ((or '&keys '&key '&allow-other-keys) (setq state 'ignore))
           (_ (pcase state
                ('required (push spec required))
                ('optional (push spec optional))
                ('rest (setq rest spec))))))
       (list :required (nreverse required)
             :optional (nreverse optional)
             :rest rest)))
    (_ nil)))

(provide 'elistan-source)
;;; elistan-source.el ends here
