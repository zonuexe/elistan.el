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
(require 'elistan-type)

(ert-deftest elistan-struct-defstruct ()
  "cl-defstruct registers predicate, constructor, copier and accessors."
  (with-temp-buffer
    (insert "(cl-defstruct foo aa bb)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'foo-p db)) '(function (t) (:guard! (:class foo)))))
      (should (equal (cdr (assq 'make-foo db)) '(function (&rest mixed) (:class foo))))
      (should (equal (cdr (assq 'foo-aa db)) '(function ((:class foo)) mixed)))
      (should (equal (cdr (assq 'foo-bb db)) '(function ((:class foo)) mixed)))
      (should (equal (cdr (assq 'copy-foo db))
                     '(function ((:class foo)) (:class foo)))))))

(ert-deftest elistan-struct-defstruct-options ()
  "A defstruct with custom :conc-name / :copier names is honoured."
  (with-temp-buffer
    (insert "(cl-defstruct (bar (:conc-name bar->) (:copier clone-bar)) xx)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'bar-p db)) '(function (t) (:guard! (:class bar)))))
      (should (assq 'bar->xx db))
      ;; The custom copier name is registered; the default copy-bar is not.
      (should (equal (cdr (assq 'clone-bar db))
                     '(function ((:class bar)) (:class bar))))
      (should-not (assq 'copy-bar db)))))

(ert-deftest elistan-struct-defclass ()
  "defclass registers predicate, constructor and :accessor slots."
  (with-temp-buffer
    (insert "(defclass baz () ((x :initarg :x :accessor baz-x)) :abstract nil)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'baz-p db)) '(function (t) (:guard! (:class baz)))))
      (should (equal (cdr (assq 'baz db)) '(function (&rest mixed) (:class baz))))
      (should (equal (cdr (assq 'baz-x db)) '(function ((:class baz)) mixed))))))

(ert-deftest elistan-struct-defclass-reader ()
  "A defclass slot `:reader' registers a reader like `:accessor' does."
  (with-temp-buffer
    (insert "(defclass rdr ()"
            " ((x :type integer :reader rdr-x)"
            "  (y :type string :accessor rdr-y :reader rdr-get-y)))\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'rdr-x db)) '(function ((:class rdr)) integer)))
      ;; A slot with both :accessor and :reader registers both.
      (should (equal (cdr (assq 'rdr-y db)) '(function ((:class rdr)) string)))
      (should (equal (cdr (assq 'rdr-get-y db))
                     '(function ((:class rdr)) string))))))

(ert-deftest elistan-struct-defstruct-slot-type ()
  "A defstruct slot `:type' (with a non-nil default) is the accessor return."
  (with-temp-buffer
    (insert "(cl-defstruct qux"
            " (aa 0 :type integer)"
            " (bb \"\" :read-only t :type string)"
            " (cc t :type boolean)"
            " dd)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'qux-aa db)) '(function ((:class qux)) integer)))
      ;; :type after another keyword is still found.
      (should (equal (cdr (assq 'qux-bb db)) '(function ((:class qux)) string)))
      (should (equal (cdr (assq 'qux-cc db)) '(function ((:class qux)) boolean)))
      ;; No :type stays `mixed'.
      (should (equal (cdr (assq 'qux-dd db)) '(function ((:class qux)) mixed))))))

(ert-deftest elistan-struct-defstruct-nil-default-widens ()
  "A nil (or absent) default widens a non-nil `:type' with nil.
`cl-defstruct' does not enforce `:type', so the slot really starts nil; the
accessor return must admit nil or `(if (NAME-slot x) ...)' would be misread."
  (with-temp-buffer
    (insert "(cl-defstruct opt"
            " (a nil :type integer)"   ; explicit nil default
            " (b :type integer))\n")   ; default value is `:type' (a symbol)
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'opt-a db))
                     '(function ((:class opt)) (or integer null))))
      ;; `(b :type integer)' parses as default `:type' (non-nil) so `b' is not
      ;; widened; the bogus keyword leaves no real `:type', hence `mixed'.
      (should (equal (cdr (assq 'opt-b db)) '(function ((:class opt)) mixed))))))

(ert-deftest elistan-struct-defstruct-docstring ()
  "A leading docstring in the body is skipped, not read as a slot."
  (with-temp-buffer
    (insert "(cl-defstruct (sess (:conc-name sess-))"
            " \"Doc string for the struct.\""
            " (n 0 :type integer) m)\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'sess-n db)) '(function ((:class sess)) integer)))
      (should (equal (cdr (assq 'sess-m db)) '(function ((:class sess)) mixed)))
      ;; The docstring produced no spurious accessor.
      (should-not (assq 'sess-Doc db)))))

(ert-deftest elistan-struct-defclass-slot-type ()
  "A defclass slot `:type' becomes the accessor's return type."
  (with-temp-buffer
    (insert "(defclass cls ()"
            " ((x :initarg :x :type string :accessor cls-x)"
            "  (y :initarg :y :accessor cls-y)))\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'cls-x db)) '(function ((:class cls)) string)))
      (should (equal (cdr (assq 'cls-y db)) '(function ((:class cls)) mixed)))))
  ;; An explicit `:initform nil' widens the type (absent :initform = unbound,
  ;; which is not nil, so it does not widen).
  (with-temp-buffer
    (insert "(defclass clz ()"
            " ((aa :type integer :initform nil :accessor clz-aa)"
            "  (bb :type integer :accessor clz-bb)))\n")
    (let ((db (elistan-struct-parse-buffer)))
      (should (equal (cdr (assq 'clz-aa db))
                     '(function ((:class clz)) (or integer null))))
      (should (equal (cdr (assq 'clz-bb db)) '(function ((:class clz)) integer))))))

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
  ;; Parameterised containers widen to the bare container type.
  (should (equal (elistan-struct--translate-type '(list-of foo)) 'list))
  (should (equal (elistan-struct--translate-type '(vector integer 3)) 'vector))
  (should (equal (elistan-struct--translate-type '(simple-vector 4)) 'vector))
  (should (equal (elistan-struct--translate-type '(array t)) 'array))
  (should (equal (elistan-struct--translate-type '(string 10)) 'string))
  (should (equal (elistan-struct--translate-type '(cons integer string)) 'cons))
  ;; Degenerate forms that would evaluate to `never' fall back to `mixed'.
  (should (equal (elistan-struct--translate-type '(or)) 'mixed))
  (should (equal (elistan-struct--translate-type '(member)) 'mixed))
  (should (equal (elistan-struct--translate-type '(integer 5 1)) 'mixed))
  (should (equal (elistan-struct--translate-type '(integer (0) 10)) 'mixed))
  ;; Forms typespec does not model are conservatively widened.
  (should (equal (elistan-struct--translate-type '(satisfies foop)) 'mixed))
  (should (equal (elistan-struct--translate-type '(and integer string)) 'mixed)))

(ert-deftest elistan-struct-predicate-narrows ()
  "A struct predicate narrows the tested variable to the class type."
  (let ((elistan-source-local '((foo-p . (function (t) (:guard! (:class foo))))))
        (env (elistan-env-make '((x . unknown)))))
    (let ((r (elistan-recognise '(foo-p x) env)))
      (should (equal (cadr (assq 'x r)) '(:class foo))))))

(ert-deftest elistan-struct-hierarchy ()
  "The class hierarchy is read from defstruct :include and defclass parents."
  (with-temp-buffer
    (insert "(cl-defstruct animal a)\n"
            "(cl-defstruct (dog (:include animal)) d)\n"
            "(defclass widget () ())\n"
            "(defclass button (widget clickable) ())\n")
    (let ((h (elistan-struct-parse-hierarchy)))
      (should (equal (cdr (assq 'dog h)) '(animal)))
      (should (equal (cdr (assq 'button h)) '(widget clickable)))
      ;; A root struct/class with no parent is not listed.
      (should-not (assq 'animal h))
      (should-not (assq 'widget h)))))

(ert-deftest elistan-struct-inherited-accessors ()
  "A cl-defstruct :include child gets readers for inherited slots via its conc."
  (with-temp-buffer
    (insert "(cl-defstruct animal (name \"\" :type string))\n"
            "(cl-defstruct (dog (:include animal)) (breed nil :type symbol))\n"
            "(cl-defstruct (puppy (:include dog)) cute)\n")
    (let ((db (elistan-struct-parse-buffer)))
      ;; own accessor (nil default widens symbol with null)
      (should (equal (cdr (assq 'dog-breed db))
                     '(function ((:class dog)) (or symbol null))))
      ;; inherited from animal via dog's conc-name, keeping animal's slot type
      (should (equal (cdr (assq 'dog-name db))
                     '(function ((:class dog)) string)))
      ;; transitive: puppy inherits both dog-breed's and animal's slots
      (should (equal (cdr (assq 'puppy-name db))
                     '(function ((:class puppy)) string)))
      (should (equal (cdr (assq 'puppy-breed db))
                     '(function ((:class puppy)) (or symbol null))))
      ;; the parent's own accessor is unchanged
      (should (equal (cdr (assq 'animal-name db))
                     '(function ((:class animal)) string))))))

(ert-deftest elistan-struct-subclass-accepted ()
  "With the hierarchy supplied, a subclass instance is accepted where the
superclass is wanted, and the predicate narrows a superclass var to the
subclass."
  (let ((typespec-eval-types-class-parents '((dog animal))))
    ;; A `(:class dog)' value is consistent with a `(:class animal)' parameter.
    (should (elistan-type-consistent-p '(:class dog) '(:class animal)))
    ;; Narrowing a `(:class animal)' var with `(dog-p x)' yields `(:class dog)'.
    (should (equal (elistan-type-meet '(:class animal) '(:class dog))
                   '(:class dog)))
    ;; Unrelated classes are still accepted (no false positive).
    (should (elistan-type-consistent-p '(:class cat) '(:class animal)))))

(provide 'elistan-struct-test)
;;; elistan-struct-test.el ends here
