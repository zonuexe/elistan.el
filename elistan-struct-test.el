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

(ert-deftest elistan-struct-defstruct-slot-type ()
  "A defstruct slot `:type' (with a non-nil default) is the accessor return."
  (with-temp-buffer
    (insert "(cl-defstruct qux"
            " (aa 0 :type integer)"
            " (bb \"\" :read-only t :type string)"
            " (cc t :type boolean)"
            " dd)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'qux-aa db)) '(function (qux) integer)))
      ;; :type after another keyword is still found.
      (should (equal (cdr (assq 'qux-bb db)) '(function (qux) string)))
      ;; boolean is spelled as the explicit t/nil union (typespec quirk).
      (should (equal (cdr (assq 'qux-cc db)) '(function (qux) (or (const t) null))))
      ;; No :type stays `mixed'.
      (should (equal (cdr (assq 'qux-dd db)) '(function (qux) mixed))))))

(ert-deftest elistan-struct-defstruct-nil-default-widens ()
  "A nil (or absent) default widens a non-nil `:type' with nil.
`cl-defstruct' does not enforce `:type', so the slot really starts nil; the
accessor return must admit nil or `(if (NAME-slot x) ...)' would be misread."
  (with-temp-buffer
    (insert "(cl-defstruct opt"
            " (a nil :type integer)"   ; explicit nil default
            " (b :type integer))\n")   ; default value is `:type' (a symbol)
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'opt-a db)) '(function (opt) (or integer null))))
      ;; `(b :type integer)' parses as default `:type' (non-nil) so `b' is not
      ;; widened; the bogus keyword leaves no real `:type', hence `mixed'.
      (should (equal (cdr (assq 'opt-b db)) '(function (opt) mixed))))))

(ert-deftest elistan-struct-defstruct-docstring ()
  "A leading docstring in the body is skipped, not read as a slot."
  (with-temp-buffer
    (insert "(cl-defstruct (sess (:conc-name sess-))"
            " \"Doc string for the struct.\""
            " (n 0 :type integer) m)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'sess-n db)) '(function (sess) integer)))
      (should (equal (cdr (assq 'sess-m db)) '(function (sess) mixed)))
      ;; The docstring produced no spurious accessor.
      (should-not (assq 'sess-Doc db)))))

(ert-deftest elistan-struct-defclass-slot-type ()
  "A defclass slot `:type' becomes the accessor's return type."
  (with-temp-buffer
    (insert "(defclass cls ()"
            " ((x :initarg :x :type string :accessor cls-x)"
            "  (y :initarg :y :accessor cls-y)))\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'cls-x db)) '(function (cls) string)))
      (should (equal (cdr (assq 'cls-y db)) '(function (cls) mixed)))))
  ;; An explicit `:initform nil' widens the type (absent :initform = unbound,
  ;; which is not nil, so it does not widen).
  (with-temp-buffer
    (insert "(defclass clz ()"
            " ((aa :type integer :initform nil :accessor clz-aa)"
            "  (bb :type integer :accessor clz-bb)))\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'clz-aa db)) '(function (clz) (or integer null))))
      (should (equal (cdr (assq 'clz-bb db)) '(function (clz) integer))))))

(ert-deftest elistan-struct-translate-type ()
  "The slot-type translator is precise where safe and `mixed' otherwise."
  (should (equal (elistan-struct--translate-type 'integer) 'integer))
  (should (equal (elistan-struct--translate-type 'string) 'string))
  (should (equal (elistan-struct--translate-type 'null) 'null))
  ;; An opaque class/alias name is kept (never provably disjoint -> no FP).
  (should (equal (elistan-struct--translate-type 'my-class) 'my-class))
  ;; Top / empty / missing all stay maximally permissive.
  (should (equal (elistan-struct--translate-type t) 'mixed))
  (should (equal (elistan-struct--translate-type nil) 'mixed))
  ;; Compound forms typespec models.
  (should (equal (elistan-struct--translate-type '(or integer string))
                 '(or integer string)))
  (should (equal (elistan-struct--translate-type '(integer 0 10))
                 '(integer 0 10)))
  (should (equal (elistan-struct--translate-type '(member a b)) '(member a b)))
  (should (equal (elistan-struct--translate-type '(eql 5)) '(const 5)))
  ;; Degenerate forms that would evaluate to `never' fall back to `mixed'.
  (should (equal (elistan-struct--translate-type '(or)) 'mixed))
  (should (equal (elistan-struct--translate-type '(member)) 'mixed))
  (should (equal (elistan-struct--translate-type '(integer 5 1)) 'mixed))
  (should (equal (elistan-struct--translate-type '(integer (0) 10)) 'mixed))
  ;; Forms typespec does not model are conservatively widened.
  (should (equal (elistan-struct--translate-type '(satisfies foop)) 'mixed))
  (should (equal (elistan-struct--translate-type '(and integer string)) 'mixed)))

(ert-deftest elistan-struct-predicate-narrows ()
  "A struct predicate narrows the tested variable to the struct type."
  (let ((elistan-source-local '((foo-p . (function (t) (:guard! foo)))))
        (env (elistan-env-make '((x . unknown)))))
    (let ((r (elistan-recognise '(foo-p x) env)))
      (should (equal (cadr (assq 'x r)) 'foo)))))

(provide 'elistan-struct-test)
;;; elistan-struct-test.el ends here
