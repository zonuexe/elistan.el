;;; elistan-project.el --- Project-wide (cross-file) checking  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  USAMI Kenta

;; Author: USAMI Kenta <tadsan@zonu.me>
;; Keywords: lisp, extensions, tools
;; License: GPL-3.0-or-later

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

;; Project-wide checking (docs/adr/0013 — a cross-file mode): a first pass
;; collects the in-file type annotations of every file in the project into one
;; registry; a second pass checks each file with that registry visible.  A
;; function annotated in one file is then an author-written contract for calls
;; in any other file, so cross-file argument mismatches are reported (ADR-0014).
;;
;; This is per-defun analysis with a shared type source — it does not infer
;; types across files (ADR-0002); it makes declared types project-visible.

;;; Code:

(require 'elistan-batch)
(require 'elistan-elsa)
(require 'elistan-struct)
(require 'elistan-declare)

(defun elistan-project-registry (files)
  "Collect in-file annotations from all FILES into one NAME -> funspec alist.
The first annotation seen for a name wins."
  (let ((acc nil))
    (dolist (file files (nreverse acc))
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (dolist (cell (append (elistan-declare-parse-buffer)
                                (elistan-elsa-parse-buffer)
                                (elistan-struct-parse-buffer)))
            (unless (assq (car cell) acc) (push cell acc))))))))

(defun elistan-project-hierarchy (files)
  "Collect the class hierarchy from all FILES into one CLASS -> (PARENT...) alist.
The first definition seen for a class wins."
  (let ((acc nil))
    (dolist (file files (nreverse acc))
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (dolist (cell (elistan-struct-parse-hierarchy))
            (unless (assq (car cell) acc) (push cell acc))))))))

(defun elistan-project-check (files)
  "Check FILES as a project; return an alist of FILE -> list of report strings.
Annotations from any file are visible to all (cross-file contract checking)."
  (let ((elistan-source-local (elistan-project-registry files))
        (typespec-eval-types-class-parents (elistan-project-hierarchy files)))
    (mapcar (lambda (f) (cons f (elistan-batch-check-file f))) files)))

(defun elistan-project-run ()
  "Batch entry: check the files in `command-line-args-left' as one project.
Prints reports and exits non-zero when any finding is produced."
  (let ((any nil))
    (dolist (entry (elistan-project-check command-line-args-left))
      (dolist (report (cdr entry))
        (setq any t)
        (princ report)
        (terpri)))
    (kill-emacs (if any 1 0))))

(provide 'elistan-project)
;;; elistan-project.el ends here
