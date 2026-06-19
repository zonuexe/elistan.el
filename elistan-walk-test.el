;;; elistan-walk-test.el --- Tests for elistan-walk  -*- lexical-binding: t; -*-

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

;; End-to-end tests for the analysis walker over whole defuns.

;;; Code:

(require 'ert)
(require 'elistan-walk)

(defun elistan-walk-test--declare (sym spec)
  "Give SYM the declared typespec SPEC for the duration of a test."
  (function-put sym 'typespec (list :spec spec)))

(defun elistan-walk-test--of (findings category)
  "Return the first finding in FINDINGS with CATEGORY, or nil."
  (seq-find (lambda (f) (eq (elistan-finding-category f) category)) findings))

(ert-deftest elistan-walk-call-mismatch ()
  "A provably incompatible argument is reported (category 1)."
  (elistan-walk-test--declare 'et-need-string '(function (string) integer))
  (elistan-walk-test--declare 'et-caller '(function (integer) integer))
  (let* ((fs (elistan-walk-defun '(defun et-caller (n) (et-need-string n))))
         (f (elistan-walk-test--of fs 'call-type-mismatch)))
    (should f)
    (should (equal (plist-get (elistan-finding-data f) :expected) 'string))
    (should (equal (plist-get (elistan-finding-data f) :actual) 'integer))
    (should (= (plist-get (elistan-finding-data f) :arg-index) 0))
    ;; no spurious return-type finding (caller returns integer as declared).
    (should-not (elistan-walk-test--of fs 'return-type-mismatch))))

(ert-deftest elistan-walk-dead-branch ()
  "Narrowing that makes a branch impossible is reported (category 2)."
  (elistan-walk-test--declare 'et-g '(function (string) integer))
  (let* ((fs (elistan-walk-defun '(defun et-g (x) (if (integerp x) 1 2))))
         (f (elistan-walk-test--of fs 'dead-branch)))
    (should f)
    (should (eq (plist-get (elistan-finding-data f) :verdict) 'always-false))
    (should (eq (plist-get (elistan-finding-data f) :dead-branch) 'then))))

(ert-deftest elistan-walk-return-mismatch ()
  "A body type incompatible with the declared return is reported (category 3)."
  (elistan-walk-test--declare 'et-h '(function (string) integer))
  (let* ((fs (elistan-walk-defun '(defun et-h (x) x)))
         (f (elistan-walk-test--of fs 'return-type-mismatch)))
    (should f)
    (should (equal (plist-get (elistan-finding-data f) :declared) 'integer))
    (should (equal (plist-get (elistan-finding-data f) :actual) 'string))))

(ert-deftest elistan-walk-clean ()
  "A well-typed function with full branch coverage produces no findings."
  (elistan-walk-test--declare 'et-ok '(function ((or string integer)) string))
  (should-not
   (elistan-walk-defun
    '(defun et-ok (x) (if (stringp x) x (number-to-string x))))))

(ert-deftest elistan-walk-guard-clause-narrowing ()
  "An early-exit guard narrows the fall-through path (divergence-aware join)."
  ;; After `(when (stringp x) (error ...))', x is integer; a later `(stringp x)'
  ;; is then provably false -> a dead-branch finding.  Without the guard there is
  ;; no such finding (stringp could go either way).  This isolates the narrowing.
  (elistan-walk-test--declare 'et-guard '(function ((or string integer)) integer))
  (should (elistan-walk-test--of
           (elistan-walk-defun
            '(defun et-guard (x)
               (when (stringp x) (error "no strings"))
               (if (stringp x) 1 2)))
           'dead-branch))
  (elistan-walk-test--declare 'et-noguard '(function ((or string integer)) integer))
  (should-not (elistan-walk-test--of
               (elistan-walk-defun '(defun et-noguard (x) (if (stringp x) 1 2)))
               'dead-branch)))

(ert-deftest elistan-walk-loop-no-false-positive ()
  "A mutating loop widens assigned variables and emits no spurious findings."
  (elistan-walk-test--declare 'et-loop '(function (integer) integer))
  (should-not
   (elistan-walk-defun
    '(defun et-loop (n)
       (let ((acc 0))
         (while (> n 0)
           (setq acc (+ acc n))
           (setq n (1- n)))
         acc)))))

(ert-deftest elistan-walk-non-defun ()
  "Non-function-defining top-level forms are out of scope."
  (should-not (elistan-walk-form '(defvar foo nil)))
  (should-not (elistan-walk-form '(message "hi"))))

(provide 'elistan-walk-test)
;;; elistan-walk-test.el ends here
