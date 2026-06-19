;;; elistan-type-test.el --- Tests for elistan-type  -*- lexical-binding: t; -*-

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

;; Tests for the gradual type-operation facade.

;;; Code:

(require 'ert)
(require 'elistan-type)

(ert-deftest elistan-type-dynamic ()
  "The dynamic is recognised bare and inside a union."
  (should (elistan-type-dynamic-p 'unknown))
  (should (elistan-type-dynamic-p '(or string unknown)))
  (should-not (elistan-type-dynamic-p 'string))
  (should-not (elistan-type-dynamic-p '(or string integer))))

(ert-deftest elistan-type-consistent ()
  "Gradual consistency: dynamic accepts both ways; else typespec compat."
  (should (elistan-type-consistent-p 'string 'string))
  (should (elistan-type-consistent-p 'integer '(or string integer)))
  (should-not (elistan-type-consistent-p 'integer 'string))
  ;; dynamic on either side is accepted.
  (should (elistan-type-consistent-p 'unknown 'string))
  (should (elistan-type-consistent-p 'string 'unknown))
  (should (elistan-type-consistent-p '(or string unknown) 'string)))

(ert-deftest elistan-type-meet-diff ()
  "Meet and diff, including the dynamic special cases."
  (should (equal (elistan-type-meet '(or string integer) 'string) 'string))
  (should (elistan-type-never-p (elistan-type-meet 'string 'integer)))
  (should (equal (elistan-type-meet 'unknown 'string) 'string))
  (should (equal (elistan-type-meet 'string 'unknown) 'string))
  (should (equal (elistan-type-diff '(or string integer) 'string) 'integer))
  (should (equal (elistan-type-diff 'unknown 'string) 'unknown)))

(ert-deftest elistan-type-nilness ()
  "Provable nil / non-nil membership."
  (should (elistan-type-always-nil-p 'null))
  (should (elistan-type-always-nil-p '(const nil)))
  (should-not (elistan-type-always-nil-p 'string))
  (should (elistan-type-never-nil-p 'string))
  (should (elistan-type-never-nil-p 'integer))
  (should-not (elistan-type-never-nil-p '(or string null)))
  (should-not (elistan-type-never-nil-p 'null))
  (should-not (elistan-type-never-nil-p 'unknown))
  (should-not (elistan-type-never-nil-p 'mixed)))

(provide 'elistan-type-test)
;;; elistan-type-test.el ends here
