;;; elistan-elsa-test.el --- Tests for elistan-elsa  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  USAMI Kenta

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

;; Tests for reading Elsa-style type annotations.

;;; Code:

(require 'ert)
(require 'elistan-elsa)

(ert-deftest elistan-elsa-translate ()
  "Elsa type notation translates to typespec notation."
  (should (equal (elistan-elsa--translate-type 'int) 'integer))
  (should (equal (elistan-elsa--translate-type 'bool) '(or (const t) null)))
  (should (equal (elistan-elsa--translate-type 'nil) 'null))
  (should (equal (elistan-elsa--translate-type 'string) 'string))
  (should (equal (elistan-elsa--translate-type '(is string)) '(:guard! string)))
  (should (equal (elistan-elsa--translate-type '(class elsa-form)) 'unknown))
  (should (equal (elistan-elsa--translate-type '(or int nil)) '(or integer null)))
  (should (equal (elistan-elsa--translate-type '(cons int string))
                 '(cons integer string)))
  (should (equal (elistan-elsa--translate-type '(function (int string) bool))
                 '(function (integer string) (or (const t) null)))))

(ert-deftest elistan-elsa-parse ()
  "Annotation comments are parsed; only function types are registered."
  (with-temp-buffer
    (insert ";; (foo :: (function (int) string))\n"
            "(defun foo (x) x)\n"
            ";;   (bar :: (function (string) int))\n"
            ";; (a-var :: (list int))\n")
    (let ((a (elistan-elsa-parse-buffer)))
      (should (equal (cdr (assq 'foo a)) '(function (integer) string)))
      (should (equal (cdr (assq 'bar a)) '(function (string) integer)))
      ;; non-function annotation is ignored.
      (should-not (assq 'a-var a)))))

(provide 'elistan-elsa-test)
;;; elistan-elsa-test.el ends here
