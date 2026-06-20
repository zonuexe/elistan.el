;;; elistan-declare.el --- Read in-file typespec declarations  -*- lexical-binding: t; -*-

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

;; An in-file type source (docs/adr/0002): reads the typespec function-type
;; declarations written in the analysed file itself.
;;
;; elistan reads forms without evaluating them (ADR-0008), so a function's own
;; `typespec' declaration in the file under analysis is otherwise invisible —
;; the `'typespec' function property it would set only exists once the file is
;; loaded.  This module extracts the declarations statically, exactly as the
;; Elsa annotation reader (`elistan-elsa.el') does; a driver binds the result
;; into `elistan-source-local', making the declaration an authoritative in-file
;; contract for argument checking (ADR-0014).
;;
;; Two forms are recognised:
;;
;;     (typespec #'NAME SPEC)                              ; the typespec macro
;;     (defun NAME ARGS (declare (typespec-ftype SPEC)) …) ; in-defun declaration
;;
;; The `typespec' macro is the canonical, recommended form; `typespec-ftype' is
;; typespec's experimental `declare' spec.  SPEC must be a function typespec —
;; `(function ARGS RET)' or `(:forall VARS (function …))' — matching what
;; `elistan-source-function-spec' expects; other specs are ignored.

;;; Code:

(defun elistan-declare--target-symbol (fn)
  "Return the function symbol named by a `typespec' macro FN argument.
FN may be a sharp-quoted or quoted symbol — `(function NAME)' or `(quote NAME)'
\(as written `#'NAME' or \\='NAME) — or a bare symbol."
  (pcase fn
    (`(,(or 'function 'quote) ,(and sym (pred symbolp))) sym)
    ((and sym (pred symbolp)) sym)
    (_ nil)))

(defun elistan-declare--funspec-p (spec)
  "Return non-nil if SPEC is a function typespec elistan can consume."
  (memq (car-safe spec) '(function :forall)))

(defun elistan-declare--declared-ftype (body)
  "Return the `typespec-ftype' spec declared in defun BODY, or nil.
Tolerant of improper/dotted lists, which can occur in generated source."
  (and (proper-list-p body)
       (seq-some
        (lambda (f)
          (and (eq (car-safe f) 'declare)
               (proper-list-p f)
               (seq-some (lambda (d)
                           (and (eq (car-safe d) 'typespec-ftype)
                                (proper-list-p d)
                                (cadr d)))
                         (cdr f))))
        body)))

(defun elistan-declare--defun-typespec (form)
  "Return (NAME . SPEC) when FORM is a defun declaring a `typespec-ftype'.
Returns nil for any other form, or a defun without such a declaration."
  (pcase form
    (`(,(or 'defun 'cl-defun 'defun* 'defsubst 'cl-defsubst)
       ,(and name (pred symbolp)) ,_args . ,body)
     (let ((spec (elistan-declare--declared-ftype body)))
       (and (elistan-declare--funspec-p spec) (cons name spec))))
    (_ nil)))

(defun elistan-declare-parse-buffer ()
  "Scan the current buffer for in-file typespec declarations.
Return an alist of NAME -> funspec for `(typespec FN SPEC)' forms and for
defuns carrying a `(declare (typespec-ftype SPEC))'."
  (let ((result nil))
    (save-excursion
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (pcase form
                (`(typespec ,fn ,spec . ,_)
                 (let ((name (elistan-declare--target-symbol fn)))
                   (when (and name (elistan-declare--funspec-p spec))
                     (push (cons name spec) result))))
                (_
                 (let ((cell (elistan-declare--defun-typespec form)))
                   (when cell (push cell result)))))))
        ((end-of-file invalid-read-syntax) nil)))
    (nreverse result)))

(provide 'elistan-declare)
;;; elistan-declare.el ends here
