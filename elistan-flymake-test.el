;;; elistan-flymake-test.el --- Tests for elistan-flymake  -*- lexical-binding: t; -*-

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

;; Tests for the Flymake backend: buffer -> findings -> diagnostics.

;;; Code:

(require 'ert)
(require 'elistan-flymake)

(ert-deftest elistan-flymake-backend-reports ()
  "The backend turns a type error into a buffer-located Flymake diagnostic."
  (function-put 'et-fly-need 'typespec '(:spec (function (string) integer)))
  (function-put 'et-fly 'typespec '(:spec (function (integer) integer)))
  (with-temp-buffer
    (insert "(defun et-fly (n)\n  (et-fly-need n))\n")
    (let (captured)
      (elistan-flymake-backend (lambda (diags) (setq captured diags)))
      (should (= (length captured) 1))
      (let ((d (car captured)))
        (should (eq (flymake-diagnostic-type d) :warning))
        (should (string-match-p "expected string" (flymake-diagnostic-text d)))
        ;; the diagnostic points inside the buffer.
        (should (<= (point-min) (flymake-diagnostic-beg d)))
        (should (<= (flymake-diagnostic-beg d) (flymake-diagnostic-end d)))))))

(ert-deftest elistan-flymake-clean-buffer ()
  "A buffer with no analysable issue yields no diagnostics."
  (with-temp-buffer
    (insert "(defun et-fly-ok (x) x)\n")
    (let ((captured 'unset))
      (elistan-flymake-backend (lambda (diags) (setq captured diags)))
      (should (null captured)))))

(provide 'elistan-flymake-test)
;;; elistan-flymake-test.el ends here
