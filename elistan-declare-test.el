;;; elistan-declare-test.el --- Tests for elistan-declare  -*- lexical-binding: t; -*-

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

;; Tests for reading in-file `typespec' / `typespec-ftype' declarations.

;;; Code:

(require 'ert)
(require 'elistan-declare)

(ert-deftest elistan-declare-typespec-macro ()
  "The `typespec' macro is read for `#'', \\=' and bare-symbol targets."
  (with-temp-buffer
    (insert "(typespec #'aa (function (string) integer))\n"
            "(typespec 'bb (:forall (a) (function (a) a)))\n"
            "(typespec cc (function () t))\n")
    (let ((db (elistan-declare-parse-buffer)))
      (should (equal (cdr (assq 'aa db)) '(function (string) integer)))
      (should (equal (cdr (assq 'bb db)) '(:forall (a) (function (a) a))))
      (should (equal (cdr (assq 'cc db)) '(function () t))))))

(ert-deftest elistan-declare-ignores-non-function-spec ()
  "A `typespec' whose spec is not a function/`:forall' is ignored."
  (with-temp-buffer
    (insert "(typespec #'dd integer)\n"
            "(typespec #'ee (or string null))\n")
    (let ((db (elistan-declare-parse-buffer)))
      (should-not (assq 'dd db))
      (should-not (assq 'ee db)))))

(ert-deftest elistan-declare-defun-declaration ()
  "A defun body `(declare (typespec-ftype SPEC))' is read."
  (with-temp-buffer
    (insert "(defun ff (n)\n"
            "  \"Double N.\"\n"
            "  (declare (indent 1) (typespec-ftype (function (number) number)))\n"
            "  (* n 2))\n"
            "(cl-defun gg (x) (declare (typespec-ftype (function (string) t))) x)\n"
            "(defun hh (x) x)\n")
    (let ((db (elistan-declare-parse-buffer)))
      (should (equal (cdr (assq 'ff db)) '(function (number) number)))
      (should (equal (cdr (assq 'gg db)) '(function (string) t)))
      ;; A defun with no typespec declaration is not registered.
      (should-not (assq 'hh db)))))

(ert-deftest elistan-declare-robust-to-junk ()
  "Unreadable trailing input does not lose earlier declarations."
  (with-temp-buffer
    (insert "(typespec #'ii (function (string) integer))\n"
            "(this is not closed\n")
    (let ((db (elistan-declare-parse-buffer)))
      (should (equal (cdr (assq 'ii db)) '(function (string) integer))))))

(ert-deftest elistan-declare-robust-to-dotted ()
  "A dotted/improper defun form is skipped, not a crash."
  (with-temp-buffer
    (insert "(defun jj (x) (foo) . bar)\n"
            "(typespec #'kk (function (string) integer))\n")
    (let ((db (elistan-declare-parse-buffer)))
      (should-not (assq 'jj db))
      (should (equal (cdr (assq 'kk db)) '(function (string) integer))))))

(provide 'elistan-declare-test)
;;; elistan-declare-test.el ends here
