;;; elistan-source-test.el --- Tests for elistan-source  -*- lexical-binding: t; -*-

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

;; Tests for function type-source resolution.

;;; Code:

(require 'ert)
(require 'elistan-source)

(ert-deftest elistan-source-resolve ()
  "Resolution falls through declaration -> typespec builtins -> fallback."
  ;; elistan fallback (predicate)
  (should (equal (elistan-source-function-spec 'stringp)
                 '(function (t) (:guard! string))))
  ;; typespec's own builtin registry
  (should (equal (elistan-source-function-spec 'memq)
                 '(function (t list) (or (list+ t) (const nil)))))
  ;; non-returning
  (should (equal (elistan-source-return (elistan-source-function-spec 'error))
                 'never))
  ;; unknown -> nil
  (should-not (elistan-source-function-spec 'elistan-no-such-fn-xyz))
  ;; a user declaration wins over everything.
  (let ((sym (make-symbol "tmp")))
    (function-put sym 'typespec '(:spec (function (string) integer)))
    (should (equal (elistan-source-function-spec sym)
                   '(function (string) integer)))))

(ert-deftest elistan-source-return-and-arglist ()
  "Return-type extraction and arglist splitting."
  (should (equal (elistan-source-return '(function (string) integer)) 'integer))
  (should (equal (elistan-source-arglist
                  '(function (string &optional integer &rest symbol) t))
                 '(:required (string) :optional (integer) :rest symbol)))
  (should (equal (elistan-source-arglist '(function (string string) t))
                 '(:required (string string) :optional nil :rest nil))))

(provide 'elistan-source-test)
;;; elistan-source-test.el ends here
