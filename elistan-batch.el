;;; elistan-batch.el --- Batch / CLI driver for elistan  -*- lexical-binding: t; -*-

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

;; The batch driver (docs/adr/0001, 0008): reads a file's top-level forms and
;; runs the analysis core, reporting `FILE:LINE:COL: SEVERITY: MESSAGE'.
;; Unreadable forms are skipped (ADR-0008).  Positions come from
;; `read-positioning-symbols' where available.
;;
;; Forms are read, not evaluated, but in-file type sources are still extracted
;; statically and merged into `elistan-source-local': Elsa `:: ' annotations
;; (`elistan-elsa.el'), `cl-defstruct'/`defclass' definitions
;; (`elistan-struct.el'), and `(typespec …)' / `(declare (typespec-ftype …))'
;; declarations (`elistan-declare.el').  Other function types come from
;; already-loaded declarations, typespec builtins, and elistan's fallback
;; (ADR-0002).

;;; Code:

(require 'elistan-walk)
(require 'elistan-elsa)
(require 'elistan-struct)
(require 'elistan-declare)

(defun elistan-batch--read-buffer ()
  "Read all top-level forms from the current buffer, skipping unreadable input.
Symbols carry source positions when `read-positioning-symbols' is available."
  (let ((reader (if (fboundp 'read-positioning-symbols)
                    #'read-positioning-symbols #'read))
        (forms nil))
    (goto-char (point-min))
    (condition-case nil
        (while t (push (funcall reader (current-buffer)) forms))
      ((end-of-file invalid-read-syntax) nil))
    (nreverse forms)))

(defun elistan-batch--format (file finding)
  "Render FINDING for FILE as `FILE:LINE:COL: SEVERITY: MESSAGE'.
Assumes the analysed buffer is current (for position lookup)."
  (let* ((pos (elistan-finding-pos finding))
         (line (if pos (line-number-at-pos pos) 1))
         (col (if pos (save-excursion (goto-char pos) (1+ (current-column))) 1)))
    (format "%s:%d:%d: %s: %s"
            file line col
            (substring (symbol-name (elistan-finding-severity finding)) 1)
            (elistan-finding-message finding))))

(defun elistan-batch-check-file (file)
  "Analyse FILE and return a list of report strings, one per finding."
  (with-temp-buffer
    (insert-file-contents file)
    (let* (;; File-local annotations take priority, but any already-bound
           ;; `elistan-source-local' (e.g. a project-wide registry) remains
           ;; visible as a fallback.
           (elistan-source-local (append (elistan-declare-parse-buffer)
                                         (elistan-elsa-parse-buffer)
                                         (elistan-struct-parse-buffer)
                                         elistan-source-local))
           ;; In-file class hierarchy feeds typespec's `(:class …)' subtyping.
           (typespec-eval-types-class-parents
            (append (elistan-struct-parse-hierarchy)
                    typespec-eval-types-class-parents))
           ;; In-file slot types feed `oref'/`slot-value' result typing.
           (elistan-walk-class-slots
            (append (elistan-struct-parse-class-slots)
                    elistan-walk-class-slots))
           ;; Skip findings with no source position: they are macro-introduced
           ;; and not user-actionable (the editor driver skips them likewise).
           (findings (seq-filter #'elistan-finding-pos
                                 (elistan-check-forms (elistan-batch--read-buffer)))))
      (mapcar (lambda (f) (elistan-batch--format file f)) findings))))

(defun elistan-batch-run ()
  "Batch entry point: analyse each file in `command-line-args-left'.
Prints reports and exits non-zero when any finding is produced."
  (let ((any nil))
    (dolist (file command-line-args-left)
      (dolist (report (elistan-batch-check-file file))
        (setq any t)
        (princ report)
        (terpri)))
    (kill-emacs (if any 1 0))))

(provide 'elistan-batch)
;;; elistan-batch.el ends here
