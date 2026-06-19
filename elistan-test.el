;;; elistan-test.el --- Tests for elistan  -*- lexical-binding: t; -*-

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

;; Tests for the elistan type environment and branch narrowing.

;;; Code:

(require 'ert)
(require 'elistan)

(ert-deftest elistan-env ()
  "Type environment: get/set, branch narrowing, and join."
  ;; get / set with default; set is functional (no mutation).
  (let ((env (elistan-env-make '((x . string)))))
    (should (equal (elistan-env-get env 'x) 'string))
    (should (equal (elistan-env-get env 'y) 'unknown))
    (should (equal (elistan-env-get (elistan-env-set env 'y 'integer) 'y) 'integer))
    (should (equal (elistan-env-get env 'y) 'unknown)))
  ;; `:guard!' narrowing then join recovers the original union.
  (let* ((env (elistan-env-make '((x . (or string integer)))))
         (b (elistan-env-narrow env 'x '(function (unknown) (:guard! string)))))
    (should (equal (elistan-env-get (plist-get b :true) 'x) 'string))
    (should (equal (elistan-env-get (plist-get b :false) 'x) 'integer))
    (should (equal (elistan-env-get
                    (elistan-env-join (plist-get b :true) (plist-get b :false))
                    'x)
                   '(or string integer))))
  ;; `:guard' leaves the false branch unchanged.
  (let* ((env (elistan-env-make '((x . unknown))))
         (b (elistan-env-narrow env 'x '(function (unknown) (:guard string)))))
    (should (equal (elistan-env-get (plist-get b :true) 'x) 'string))
    (should (equal (elistan-env-get (plist-get b :false) 'x) 'unknown)))
  ;; `:assert' produces a success environment.
  (let* ((env (elistan-env-make '((x . unknown))))
         (b (elistan-env-narrow env 'x '(function (unknown) (:assert integer)))))
    (should (equal (elistan-env-get (plist-get b :assert) 'x) 'integer)))
  ;; A non-guard predicate yields no refinement.
  (should (equal (elistan-env-narrow (elistan-env-make) 'x
                                     '(function (unknown) boolean))
                 nil)))

(provide 'elistan-test)
;;; elistan-test.el ends here
