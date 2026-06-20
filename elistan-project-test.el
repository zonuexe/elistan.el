;;; elistan-project-test.el --- Tests for elistan-project  -*- lexical-binding: t; -*-

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

;; Tests for project-wide (cross-file) checking.

;;; Code:

(require 'ert)
(require 'elistan-project)

(ert-deftest elistan-project-cross-file ()
  "An annotation in one file checks a call in another file (project mode)."
  (let ((fa (make-temp-file
             "elp-a" nil ".el"
             ";; (p-need :: (function (string) integer))\n(defun p-need (s) 0)\n"))
        (fb (make-temp-file
             "elp-b" nil ".el"
             ";; (p-call :: (function (integer) integer))\n(defun p-call (n) (p-need n))\n")))
    (unwind-protect
        (progn
          ;; Per file: fb alone does not know p-need's type -> no finding.
          (should-not (seq-find (lambda (r) (string-match-p "expected string" r))
                                (elistan-batch-check-file fb)))
          ;; Project: p-need's annotation (from fa) is visible -> mismatch in fb.
          (let ((fb-reports (cdr (assoc fb (elistan-project-check (list fa fb))))))
            (should (seq-find
                     (lambda (r)
                       (string-match-p
                        "argument 1 has type integer, expected string" r))
                     fb-reports))))
      (delete-file fa)
      (delete-file fb))))

(ert-deftest elistan-project-registry ()
  "The registry aggregates annotations from every file."
  (let ((fa (make-temp-file "elp-a" nil ".el"
                            ";; (rf-a :: (function (string) integer))\n"))
        (fb (make-temp-file "elp-b" nil ".el"
                            ";; (rf-b :: (function (integer) string))\n")))
    (unwind-protect
        (let ((reg (elistan-project-registry (list fa fb))))
          (should (equal (cdr (assq 'rf-a reg)) '(function (string) integer)))
          (should (equal (cdr (assq 'rf-b reg)) '(function (integer) string))))
      (delete-file fa)
      (delete-file fb))))

(ert-deftest elistan-project-cross-file-inheritance ()
  "An :include parent in another file yields the child's inherited accessors."
  (let ((fa (make-temp-file
             "elp-base" nil ".el"
             "(cl-defstruct animal (name \"\" :type string))\n"))
        (fb (make-temp-file
             "elp-sub" nil ".el"
             "(cl-defstruct (dog (:include animal)) d)\n")))
    (unwind-protect
        (progn
          ;; Per file: fb alone cannot resolve `animal' -> no inherited dog-name.
          (with-temp-buffer
            (insert-file-contents fb)
            (should-not (assq 'dog-name (elistan-struct-parse-buffer))))
          ;; Project: animal's slots resolve cross-file -> dog-name registered.
          (let ((infos (elistan-project-struct-infos (list fa fb))))
            (should (equal
                     (cdr (assq 'dog-name
                                (elistan-struct--inherited-accessors-from-infos
                                 infos)))
                     '(function ((:class dog)) string)))))
      (delete-file fa)
      (delete-file fb))))

(provide 'elistan-project-test)
;;; elistan-project-test.el ends here
