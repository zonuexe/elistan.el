;;; elistan-elsa.el --- Read Elsa-style type annotations  -*- lexical-binding: t; -*-

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

;; An additional type source (docs/adr/0002, 0013): reads
;; [Elsa](https://github.com/emacs-elsa/Elsa)-style annotation comments of the
;; form
;;
;;     ;; (NAME :: TYPE)
;;
;; that precede a definition, and translates Elsa's type notation to typespec's.
;; A driver parses the file and binds the result to `elistan-source-local'
;; (elistan-source.el), so a function's declared type can come from the file
;; being analysed.  Only function-typed annotations are registered.
;;
;; The notations mostly coincide; the differences handled here are: `int' ->
;; `integer', `bool' -> `boolean', the nil type -> `null', `(is T)' (predicate
;; narrowing) -> `(:guard! T)', and constructs typespec does not model
;; (`(class X)', `(struct X)', `(diff ...)') -> `unknown'.

;;; Code:

(defun elistan-elsa--translate-type (ty)
  "Translate Elsa type notation TY to a typespec type."
  (pcase ty
    ('int 'integer)
    ;; Elsa's `bool' is *explicitly* t or nil.  Spelling it as that union
    ;; (rather than typespec's opaque `boolean') keeps narrowing precise and
    ;; sidesteps a typespec bug where `boolean' n (const nil)' yields `never'.
    ('bool '(or (const t) null))
    ('nil 'null)
    ((pred symbolp) ty)
    (`(is ,inner) (list :guard! (elistan-elsa--translate-type inner)))
    ;; EIEIO classes / structs / difference types are not modelled by typespec;
    ;; treat them as the dynamic so they never cause a false positive.
    (`(,(or 'class 'struct 'interface 'diff) . ,_) 'unknown)
    (`(const ,v) (list 'const v))
    (`(function ,args ,ret)
     (list 'function
           (mapcar #'elistan-elsa--translate-type args)
           (elistan-elsa--translate-type ret)))
    (`(,head . ,rest)
     (cons head (mapcar #'elistan-elsa--translate-type rest)))
    (_ ty)))

(defun elistan-elsa-parse-buffer ()
  "Scan the current buffer for Elsa `;; (NAME :: TYPE)' annotations.
Return an alist of NAME -> typespec funspec, for function-typed annotations."
  (let ((result nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*;;+[ \t]*\\((\\)" nil t)
        (goto-char (match-beginning 1))
        (condition-case nil
            (let ((form (read (current-buffer))))
              (when (and (consp form) (= (length form) 3) (eq (nth 1 form) '::))
                (let ((name (nth 0 form))
                      (ty (elistan-elsa--translate-type (nth 2 form))))
                  (when (and (symbolp name) (eq (car-safe ty) 'function))
                    (push (cons name ty) result)))))
          (error nil))
        (forward-line 1)))
    (nreverse result)))

(provide 'elistan-elsa)
;;; elistan-elsa.el ends here
