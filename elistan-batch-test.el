;;; elistan-batch-test.el --- Tests for elistan-batch  -*- lexical-binding: t; -*-

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

;; Tests for the batch / CLI driver: file -> findings -> report strings.

;;; Code:

(require 'ert)
(require 'elistan-batch)

(ert-deftest elistan-batch-reports ()
  "A file with a type error yields a `file:line:col: warning: ...' report."
  (function-put 'et-batch-need 'typespec '(:spec (function (string) integer)))
  (function-put 'et-batch-caller 'typespec '(:spec (function (integer) integer)))
  (let ((file (make-temp-file
               "elistan-batch" nil ".el"
               "(defun et-batch-caller (n)\n  (et-batch-need n))\n")))
    (unwind-protect
        (let ((reports (elistan-batch-check-file file)))
          (should (= (length reports) 1))
          (should (string-match-p "warning:" (car reports)))
          (should (string-match-p
                   "argument 1 has type integer, expected string" (car reports)))
          ;; report begins with the file path and a line:col locus.
          (should (string-match-p (concat (regexp-quote file) ":[0-9]+:[0-9]+:")
                                  (car reports))))
      (delete-file file))))

(ert-deftest elistan-batch-uses-elsa-annotations ()
  "The batch driver reads in-file Elsa `:: ' annotations and checks against them."
  (let ((file (make-temp-file
               "elistan-elsa" nil ".el"
               ";; (et-en :: (function (string) integer))\n(defun et-en (s) s)\n")))
    (unwind-protect
        ;; s is annotated `string' but the declared return is `integer'; the body
        ;; returns s -> a return mismatch is reported (only if the annotation was
        ;; read and applied).
        (should (seq-find
                 (lambda (r)
                   (string-match-p
                    "return type string is incompatible with declared integer" r))
                 (elistan-batch-check-file file)))
      (delete-file file))))

(ert-deftest elistan-batch-uses-typespec-declarations ()
  "The batch driver reads an in-file `(typespec …)' declaration and checks it."
  (let ((file (make-temp-file
               "elistan-decl" nil ".el"
               (concat "(typespec #'et-need-str (function (string) integer))\n"
                       "(defun et-need-str (s) s)\n"
                       "(defun et-call (n) (et-need-str (+ n 1)))\n"))))
    (unwind-protect
        ;; et-need-str is declared to take a string; et-call passes the result
        ;; of `(+ n 1)' (a number) -> a call mismatch, only if the in-file
        ;; declaration was read and treated as authoritative.
        (should (seq-find
                 (lambda (r)
                   (string-match-p
                    "argument 1 has type number, expected string" r))
                 (elistan-batch-check-file file)))
      (delete-file file))))

(ert-deftest elistan-batch-clean-file ()
  "A file with no analysable issues produces no reports."
  (let ((file (make-temp-file
               "elistan-batch" nil ".el"
               "(defun et-batch-ok (x) x)\n(defvar et-batch-var nil)\n")))
    (unwind-protect
        (should-not (elistan-batch-check-file file))
      (delete-file file))))

(provide 'elistan-batch-test)
;;; elistan-batch-test.el ends here
