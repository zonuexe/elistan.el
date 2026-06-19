;;; elistan-recognise-test.el --- Tests for elistan-recognise  -*- lexical-binding: t; -*-

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

;; Tests for condition recognition, refinement composition, and application.

;;; Code:

(require 'ert)
(require 'elistan-recognise)
(require 'elistan-type)

(defun elistan-recognise-test--equiv (a b)
  "Non-nil when types A and B are equivalent (consistent both ways)."
  (and (elistan-type-consistent-p a b) (elistan-type-consistent-p b a)))

(ert-deftest elistan-recognise-predicates ()
  "Guard predicates and nil-ness narrow the tested variable."
  (let ((env (elistan-env-make '((x . (or string integer))))))
    (should (equal (elistan-recognise '(stringp x) env) '((x string . integer))))
    (should (equal (elistan-recognise '(not (stringp x)) env) '((x integer . string)))))
  (let ((env (elistan-env-make '((x . (or string null))))))
    (should (equal (elistan-recognise '(null x) env) '((x null . string))))
    ;; bare variable as a test: true non-nil, false nil.
    (should (equal (elistan-recognise 'x env) '((x string . null))))))

(ert-deftest elistan-recognise-equality-and-membership ()
  "Equality-to-const and memq narrow to / away from the constant set."
  (let ((env (elistan-env-make '((x . unknown)))))
    (should (equal (elistan-recognise '(eq x 'foo) env)
                   '((x (const foo) . unknown))))
    (should (equal (elistan-recognise '(memq x '(a b)) env)
                   '((x (or (const a) (const b)) . unknown))))))

(ert-deftest elistan-recognise-comparison ()
  "Integer comparisons narrow to ranges; operand order is handled."
  (let ((env (elistan-env-make '((x . integer)))))
    (should (equal (elistan-recognise '(> x 5) env)
                   '((x (integer 6 *) integer * 5))))
    (should (equal (elistan-recognise '(< 5 x) env)
                   '((x (integer 6 *) integer * 5))))
    ;; non-integer operand: no narrowing.
    (should-not (elistan-recognise '(> x y) env)))
  ;; float variable: comparison narrowing is skipped (unsound as int range).
  (let ((env (elistan-env-make '((x . float)))))
    (should-not (elistan-recognise '(> x 5) env))))

(ert-deftest elistan-recognise-and-or ()
  "`and' is precise on true / widened on false; `or' is the dual."
  (let* ((env (elistan-env-make '((x . (or string integer)) (y . (or cons null)))))
         (r (elistan-recognise '(and (stringp x) (consp y)) env))
         (te (elistan-refine-true env r))
         (fe (elistan-refine-false env r)))
    (should (equal (elistan-env-get te 'x) 'string))
    (should (elistan-recognise-test--equiv (elistan-env-get te 'y) 'cons))
    ;; false branch widened (unchanged) for an `and'.
    (should (equal (elistan-env-get fe 'x) '(or string integer)))
    (should (equal (elistan-env-get fe 'y) '(or cons null))))
  (let* ((env (elistan-env-make '((x . (or string integer null)))))
         (r (elistan-recognise '(or (stringp x) (integerp x)) env)))
    ;; or false branch precise: neither string nor integer -> null.
    (should (equal (elistan-env-get (elistan-refine-false env r) 'x) 'null))
    ;; or true branch widened (unchanged).
    (should (equal (elistan-env-get (elistan-refine-true env r) 'x)
                   '(or string integer null)))))

(ert-deftest elistan-recognise-unrecognised ()
  "An unrecognised test yields nil; applying nil leaves the env unchanged."
  (let ((env (elistan-env-make '((x . string)))))
    (should-not (elistan-recognise '(foo x) env))
    (should (equal (elistan-refine-true env nil) env))
    (should (equal (elistan-refine-false env nil) env))))

(provide 'elistan-recognise-test)
;;; elistan-recognise-test.el ends here
