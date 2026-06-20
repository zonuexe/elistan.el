;;; elistan-struct-test.el --- Tests for elistan-struct  -*- lexical-binding: t; -*-

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

;; Tests for reading defstruct / defclass as a type source.

;;; Code:

(require 'ert)
(require 'elistan-struct)
(require 'elistan-recognise)

(ert-deftest elistan-struct-defstruct ()
  "cl-defstruct registers predicate, constructor, copier and accessors."
  (with-temp-buffer
    (insert "(cl-defstruct foo aa bb)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'foo-p db)) '(function (t) (:guard! foo))))
      (should (equal (cdr (assq 'make-foo db)) '(function (&rest mixed) foo)))
      (should (equal (cdr (assq 'foo-aa db)) '(function (foo) mixed)))
      (should (equal (cdr (assq 'foo-bb db)) '(function (foo) mixed)))
      (should (equal (cdr (assq 'copy-foo db)) '(function (foo) foo))))))

(ert-deftest elistan-struct-defstruct-options ()
  "A defstruct with a custom :conc-name is honoured."
  (with-temp-buffer
    (insert "(cl-defstruct (bar (:conc-name bar->)) xx)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'bar-p db)) '(function (t) (:guard! bar))))
      (should (assq 'bar->xx db)))))

(ert-deftest elistan-struct-defclass ()
  "defclass registers predicate, constructor and :accessor slots."
  (with-temp-buffer
    (insert "(defclass baz () ((x :initarg :x :accessor baz-x)) :abstract nil)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'baz-p db)) '(function (t) (:guard! baz))))
      (should (equal (cdr (assq 'baz db)) '(function (&rest mixed) baz)))
      (should (equal (cdr (assq 'baz-x db)) '(function (baz) mixed))))))

(ert-deftest elistan-struct-predicate-narrows ()
  "A struct predicate narrows the tested variable to the struct type."
  (let ((elistan-source-local '((foo-p . (function (t) (:guard! foo)))))
        (env (elistan-env-make '((x . unknown)))))
    (let ((r (elistan-recognise '(foo-p x) env)))
      (should (equal (cadr (assq 'x r)) 'foo)))))

(provide 'elistan-struct-test)
;;; elistan-struct-test.el ends here
